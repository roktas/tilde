#!/usr/bin/env bash

set -Eeuo pipefail
[[ -z ${TRACE:-} ]] || set -x
unset CDPATH

cleanup_tmpdir=

# ------------------------------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------------------------------

cleanup() {
	[[ -z $cleanup_tmpdir ]] || rm -rf "$cleanup_tmpdir"
}

host_name() {
	local host

	host=$(hostname -f 2>/dev/null || hostname)
	host=${host%%.*}
	printf '%s\n' "$host"
}

write_fake_packages() {
	local bindir=$1

	cat >"$bindir/brew" <<'EOF'
#!/usr/bin/env sh
if [ "${LC_ALL:-}" != en_US.UTF-8 ] || [ "${LANG:-}" != en_US.UTF-8 ]; then
	printf 'missing runtime locale: LC_ALL=%s LANG=%s\n' "${LC_ALL:-}" "${LANG:-}" >&2
	exit 9
fi

case "$*" in
"list --formula -1")
	printf 'git\n'
	;;
"list --cask -1")
	printf 'visual-studio-code\n'
	;;
*)
	printf 'unexpected brew command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	cat >"$bindir/bun" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"list -g")
	printf '%s\n' "$HOME/.bun/install/global node_modules (1)" '+-- @scope/pkg@1.0.0'
	;;
*)
	printf 'unexpected bun command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	cat >"$bindir/dpkg-query" <<'EOF'
#!/usr/bin/env sh
printf 'curl\n'
EOF
	cat >"$bindir/flatpak" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"list --app --columns=application")
	printf 'org.example.App\n'
	;;
*)
	printf 'unexpected flatpak command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	cat >"$bindir/gem" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"list --no-versions")
	printf 'rubocop\n'
	;;
*)
	printf 'unexpected gem command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	cat >"$bindir/scoop" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"list")
	printf 'Name Version Source\nless 1.0 main\n'
	;;
*)
	printf 'unexpected scoop command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	cat >"$bindir/systemctl" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"get-default")
	printf 'graphical.target\n'
	;;
"is-enabled gdm3 sddm lightdm display-manager")
	printf 'enabled\n'
	;;
*)
	exit 1
	;;
esac
EOF
	cat >"$bindir/tool" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
	cat >"$bindir/uv" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"tool list")
	printf 'ruff v1.0.0\n- ruff\n'
	;;
*)
	printf 'unexpected uv command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	chmod +x "$bindir"/*
}

write_package_repo() {
	local repo=$1

	mkdir -p "$repo/packages"

	cat >"$repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
---

# Package Apply Smoke
EOF

	cat >"$repo/packages/README.md" <<'EOF'
---
all:
  packages:
    - brew:git
    - cask:visual-studio-code
    - deb:curl
    - egg:ruff
    - flatpak:org.example.App
    - gem:rubocop
    - github:example/tool
    - npm:@scope/pkg
    - scoop:less
    - skill:github.com/example/skillfoo
---

# Packages
EOF
}

write_repo() {
	local repo=$1

	mkdir -p "$repo/app" "$repo/section"

	cat >"$repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
---

# Apply Smoke
EOF

	cat >"$repo/app/README.md" <<'EOF'
---
all:
  links:
    source.txt: ~/.config/app/source.txt
  copies:
    copy.txt: ~/.config/app/copy.txt
  seeds:
    seed.txt: ~/.config/app/seed.txt
  resets:
    reset.txt: ~/.config/app/reset.txt
---

# App
EOF
	printf 'source\n' >"$repo/app/source.txt"
	printf 'copy\n' >"$repo/app/copy.txt"
	printf 'seed\n' >"$repo/app/seed.txt"
	printf 'reset\n' >"$repo/app/reset.txt"

	cat >"$repo/section/README.md" <<'EOF'
# Section

## Install

```bash
line ensure "$HOME/.profile" 'export EDITOR=vim'
```

## Post Install

```bash
printf 'post\n' >> "$HOME/post-install"
```

## Configure

```bash
printf 'configure\n' > "$HOME/configure"
```
EOF
}

write_apt_warning_plan() {
	local file=$1
	local repo=$2
	local state=$3
	local home=$4
	local host=$5

	ruby - "$file" "$repo" "$state" "$home" "$host" <<'RUBY'
require "digest"
require "json"
require "open3"
require "time"

file, repo, state, home, host = ARGV
stdout, stderr, status = Open3.capture3("git", "-C", repo, "rev-parse", "HEAD")
raise stderr unless status.success?

dirty, stderr, status = Open3.capture3("git", "-C", repo, "status", "--porcelain")
raise stderr unless status.success?

plan = {
  "schema" => "tilde.plan/v1",
  "generated_at" => Time.now.iso8601,
  "repository" => {
    "role" => "public",
    "path" => repo,
    "commit" => stdout.strip,
    "dirty" => !dirty.empty?
  },
  "target" => {
    "host" => host,
    "platform" => "linux",
    "mode" => "refresh",
    "scope" => "fast",
    "level" => "normal",
    "home" => home,
    "state_root" => File.join(state, "tilde")
  },
  "actions" => [
    {
      "id" => "public/linux:package:refresh:deb:*",
      "kind" => "package",
      "module_id" => "public/linux",
      "repo_role" => "public",
      "operation" => "refresh",
      "package" => {
        "type" => "deb",
        "name" => "*",
        "value" => "deb:*",
        "system" => true
      }
    }
  ]
}

def canonicalize(value)
  case value
  when Array
    value.map { |item| canonicalize(item) }
  when Hash
    value.keys.map(&:to_s).sort.to_h { |key| [key, canonicalize(value[key])] }
  else
    value
  end
end

content = canonicalize(plan.reject { |key, _value| %w[generated_at plan_id].include?(key) })
plan["plan_id"] = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(content))}"
File.write(file, JSON.pretty_generate(plan))
RUBY
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local apply_json
	local apt_apply_json
	local apt_plan_json
	local conflict_apply_json
	local conflict_plan_json
	local fake_bin
	local head
	local home
	local host
	local package_apply_json
	local package_plan_json
	local package_repo
	local plan_json
	local refresh_apply_json
	local refresh_plan_json
	local refresh_state
	local repo
	local script_dir
	local second_apply_json
	local second_plan_json
	local skill_root
	local state
	local tilde
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	tilde=$skill_root/bin/tilde

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	home=$tmpdir/home
	host=$(host_name)
	repo=$home/Dropbox/home
	state=$tmpdir/state
	apply_json=$tmpdir/apply.json
	apt_apply_json=$tmpdir/apt-warning-apply.json
	apt_plan_json=$tmpdir/apt-warning-plan.json
	conflict_apply_json=$tmpdir/conflict-apply.json
	conflict_plan_json=$tmpdir/conflict-plan.json
	fake_bin=$tmpdir/fake-bin
	package_apply_json=$tmpdir/package-apply.json
	package_plan_json=$tmpdir/package-plan.json
	package_repo=$tmpdir/package-repo
	plan_json=$tmpdir/plan.json
	refresh_apply_json=$tmpdir/refresh-apply.json
	refresh_plan_json=$tmpdir/refresh-plan.json
	refresh_state=$tmpdir/refresh-state
	second_apply_json=$tmpdir/second-apply.json
	second_plan_json=$tmpdir/second-plan.json

	mkdir -p "$fake_bin" "$home/Dropbox" "$refresh_state/tilde" "$state/tilde"
	write_fake_packages "$fake_bin"
	write_repo "$repo"
	git -C "$repo" init -q
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	git -C "$repo" add .
	git -C "$repo" commit -q -m init
	head=$(git -C "$repo" rev-parse HEAD)

	HOME=$home XDG_STATE_HOME=$refresh_state "$tilde" plan --repo "$repo" --mode refresh --platform linux --host "$host" >"$refresh_plan_json"
	HOME=$home XDG_STATE_HOME=$refresh_state "$tilde" apply --plan "$refresh_plan_json" >"$refresh_apply_json"
	[[ ! -f $refresh_state/tilde/state.yml ]]

	REFRESH_APPLY_JSON=$refresh_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("REFRESH_APPLY_JSON")))
		abort "refresh apply should complete" unless apply.fetch("completed")
		abort "refresh should run configure" unless apply.fetch("results").any? { |result| result.fetch("action_id") == "public/section:section:Configure" }
	'

	mkdir -p "$home/.config/app"
	printf 'unmanaged\n' >"$home/.config/app/source.txt"
	HOME=$home XDG_STATE_HOME=$state "$tilde" plan --repo "$repo" --platform linux --host "$host" >"$conflict_plan_json"
	HOME=$home XDG_STATE_HOME=$state "$tilde" apply --plan "$conflict_plan_json" >"$conflict_apply_json"
	[[ ! -f $state/tilde/state.yml ]]

	CONFLICT_APPLY_JSON=$conflict_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("CONFLICT_APPLY_JSON")))
		conflict = apply.fetch("results").find { |result| result.fetch("kind") == "link" }
		abort "missing conflict result" unless conflict
		abort "link conflict should be reported" unless conflict.fetch("status") == "conflict"
	'

	rm -f "$home/.config/app/source.txt"
	ln -s "$repo/app/seed.txt" "$home/.config/app/seed.txt"
	ln -s "$repo/app/reset.txt" "$home/.config/app/reset.txt"
	rm -f "$home/.profile" "$home/post-install" "$home/configure"
	HOME=$home XDG_STATE_HOME=$state "$tilde" plan --repo "$repo" --platform linux --host "$host" >"$plan_json"
	HOME=$home XDG_STATE_HOME=$state "$tilde" apply --plan "$plan_json" >"$apply_json"

	[[ -L $home/.config/app/source.txt ]]
	grep -Fqx 'copy' "$home/.config/app/copy.txt"
	[[ ! -L $home/.config/app/seed.txt ]]
	[[ ! -L $home/.config/app/reset.txt ]]
	grep -Fqx 'seed' "$home/.config/app/seed.txt"
	grep -Fqx 'reset' "$home/.config/app/reset.txt"
	grep -Fqx 'configure' "$home/configure"
	grep -Fxq 'post' "$home/post-install"
	grep -Fxq 'export EDITOR=vim' "$home/.profile"
	[[ -f $state/tilde/state.yml ]]

	APPLY_JSON=$apply_json STATE_FILE=$state/tilde/state.yml HEAD=$head ruby -rjson -ryaml -e '
		apply = JSON.parse(File.read(ENV.fetch("APPLY_JSON")))
		abort "apply should complete" unless apply.fetch("completed")
		install = apply.fetch("results").find { |result| result.fetch("module_id") == "public/section" && result.dig("diagnostics", "name") == "Install" }
		abort "install section should be changed by helper JSONL" unless install&.fetch("status") == "changed"
		post = apply.fetch("results").find { |result| result.fetch("module_id") == "public/section" && result.dig("diagnostics", "name") == "Post Install" }
		abort "post install should run after changed install" unless post&.fetch("status") == "ok"
		state = YAML.safe_load(File.read(ENV.fetch("STATE_FILE")))
		abort "wrong protocol" unless state.fetch("protocol") == "tilde/v1"
		abort "wrong public anchor" unless state.fetch("applied").fetch("public") == ENV.fetch("HEAD")
		abort "state must not contain done map" if state.key?("done")
	'

	printf 'local seed\n' >"$home/.config/app/seed.txt"
	printf 'local reset\n' >"$home/.config/app/reset.txt"
	HOME=$home XDG_STATE_HOME=$state "$tilde" plan --repo "$repo" --platform linux --host "$host" >"$second_plan_json"
	HOME=$home XDG_STATE_HOME=$state "$tilde" apply --plan "$second_plan_json" >"$second_apply_json"

	[[ $(grep -c '^post$' "$home/post-install") -eq 1 ]]
	grep -Fqx 'local seed' "$home/.config/app/seed.txt"
	grep -Fqx 'reset' "$home/.config/app/reset.txt"
	SECOND_APPLY_JSON=$second_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("SECOND_APPLY_JSON")))
		post = apply.fetch("results").find { |result| result.fetch("action_id") == "public/section:section:Post Install" }
		abort "post install should be skipped when install did not change" unless post&.fetch("status") == "skipped"
		seed = apply.fetch("results").find { |result| result.fetch("action_id") == "public/app:seed:seed.txt->~/.config/app/seed.txt" }
		abort "seed should leave existing real target unchanged" unless seed&.fetch("status") == "unchanged"
		reset = apply.fetch("results").find { |result| result.fetch("action_id") == "public/app:reset:reset.txt->~/.config/app/reset.txt" }
		abort "reset should restore drifted target" unless reset&.fetch("status") == "changed"
	'

	write_package_repo "$package_repo"
	git -C "$package_repo" init -q
	git -C "$package_repo" config user.email smoke@example.invalid
	git -C "$package_repo" config user.name Smoke
	git -C "$package_repo" add .
	git -C "$package_repo" commit -q -m init
	mkdir -p "$home/.agents/skills/skillfoo/.git"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$tilde" plan --repo "$package_repo" --platform linux --host "$host" >"$package_plan_json"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$tilde" apply --plan "$package_plan_json" >"$package_apply_json"

	PACKAGE_APPLY_JSON=$package_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("PACKAGE_APPLY_JSON")))
		packages = apply.fetch("results").select { |result| result.fetch("kind") == "package" }
		abort "expected all package types" unless packages.length == 10
		bad = packages.reject { |result| result.fetch("status") == "unchanged" }
		abort "installed packages should be unchanged: #{bad.inspect}" unless bad.empty?
		ran = packages.select { |result| result.fetch("diagnostics").key?("commands") }
		abort "package install commands should not run when inventory says present: #{ran.inspect}" unless ran.empty?
	'

	cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env sh
case "$*" in
"-n env DEBIAN_FRONTEND=noninteractive apt-get update")
	printf 'W: Failed to fetch https://example.invalid stable InRelease\n' >&2
	printf 'W: Some index files failed to download. They have been ignored, or old ones used instead.\n' >&2
	exit 0
	;;
*)
	printf 'unexpected sudo command: %s\n' "$*" >&2
	exit 9
	;;
esac
EOF
	chmod +x "$fake_bin/sudo"
	write_apt_warning_plan "$apt_plan_json" "$repo" "$state" "$home" "$host"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$tilde" apply --plan "$apt_plan_json" >"$apt_apply_json"

	APT_APPLY_JSON=$apt_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("APT_APPLY_JSON")))
		result = apply.fetch("results").fetch(0)
		abort "apt warning should defer" unless result.fetch("status") == "deferred"
		abort "wrong apt warning reason" unless result.dig("diagnostics", "reason") == "apt update incomplete"
		commands = result.dig("diagnostics", "commands")
		abort "apt upgrade should not run after incomplete update" unless commands.length == 1
	'

	echo "apply smoke ok"
}

main "$@"
