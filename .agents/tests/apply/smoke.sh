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

write_repo() {
	local repo=$1

	mkdir -p \
		"$repo/aaa-link" \
		"$repo/flatpak" \
		"$repo/github" \
		"$repo/manual" \
		"$repo/pkg" \
		"$repo/section"

	cat >"$repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
  private: ../home-
---

# Apply Smoke
EOF

	cat >"$repo/aaa-link/README.md" <<'EOF'
---
all:
  links:
    source.txt: ~/Dropbox/var/app/source-link.txt
  copies:
    copy.txt: ~/.config/sample/copy.txt
---

# Link And Copy
EOF
	printf 'link\n' >"$repo/aaa-link/source.txt"
	printf 'copy\n' >"$repo/aaa-link/copy.txt"

	cat >"$repo/flatpak/README.md" <<'EOF'
---
all:
  packages:
    - flatpak:org.example.App
---

# Flatpak
EOF

	cat >"$repo/github/README.md" <<'EOF'
---
all:
  packages:
    - github:owner/tool
---

# GitHub
EOF

	cat >"$repo/manual/README.md" <<'EOF'
# Manual

## Install

Review this instruction before running the command.

```bash
printf 'manual\n' > "$HOME"/manual-ran
```
EOF

	cat >"$repo/pkg/README.md" <<'EOF'
---
all:
  packages:
    - brew:broken
---

# Package
EOF

	cat >"$repo/section/README.md" <<'EOF'
# Section

## Install

```bash
mkdir -p "$HOME"/section
printf 'section\n' > "$HOME"/section/created.txt
```
EOF
}

write_private_repo() {
	local repo=$1

	mkdir -p "$repo/home" "$repo/zzz-private"

	cat >"$repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: private
  public: ../home
---

# Private Apply Smoke
EOF

	cat >"$repo/home/README.md" <<'EOF'
---
all:
  links:
    AGENTS.md: ~/AGENTS.md
---

# Home
EOF
	printf '# Target Home\n' >"$repo/home/AGENTS.md"

	cat >"$repo/zzz-private/README.md" <<'EOF'
---
all:
  links:
    private.txt: ~/.config/private/private.txt
---

# Private
EOF
	printf 'private\n' >"$repo/zzz-private/private.txt"
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local apply
	local apply_json
	local bad_err
	local bad_condition_err
	local bad_condition_plan
	local bad_plan
	local bad_repo
	local fake_bin
	local home
	local host
	local plan
	local plan_json
	local private_plan_json
	local private_repo
	local refresh_apply_json
	local refresh_plan_json
	local repo
	local script_dir
	local skill_root
	local skip_apply_json
	local skip_plan_json
	local skip_private_plan_json
	local state
	local state_before_refresh
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	apply=$skill_root/bin/apply
	plan=$skill_root/bin/plan

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	host=$(host_name)
	home=$tmpdir/home
	state=$tmpdir/state
	repo=$home/Dropbox/src/home
	private_repo=$home/Dropbox/src/home-
	bad_repo=$tmpdir/bad-home
	fake_bin=$tmpdir/bin
	plan_json=$tmpdir/plan.json
	private_plan_json=$tmpdir/private-plan.json
	refresh_apply_json=$tmpdir/refresh-apply.json
	refresh_plan_json=$tmpdir/refresh-plan.json
	skip_apply_json=$tmpdir/skip-apply.json
	skip_plan_json=$tmpdir/skip-plan.json
	skip_private_plan_json=$tmpdir/skip-private-plan.json
	state_before_refresh=$tmpdir/state-before-refresh.md
	bad_plan=$tmpdir/bad-plan.json
	bad_condition_plan=$tmpdir/bad-condition-plan.json
	apply_json=$tmpdir/apply.json
	bad_err=$tmpdir/bad.err
	bad_condition_err=$tmpdir/bad-condition.err

	mkdir -p \
		"$fake_bin" \
		"$home/Dropbox/var/app" \
		"$home/.config/sample" \
		"$private_repo" \
		"$repo" \
		"$state/tilde"

	cat >"$fake_bin/brew" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == install && ${2:-} == broken ]]; then
	printf 'fake brew failure\n' >&2
	exit 7
fi

printf 'brew %s\n' "$*" >> "$HOME"/package-log
	exit 0
EOF
	cat >"$fake_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	cat >"$fake_bin/flatpak" <<'EOF'
#!/usr/bin/env bash
printf 'flatpak ran\n' > "$HOME"/flatpak-ran
exit 0
EOF
	cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$HOME"/package-log

if [[ ${1:-} == release && ${2:-} == view ]]; then
	printf '{"tagName":"v1.2.3","assets":[{"name":"tool_1.2.3_linux_amd64.deb"}]}\n'
	exit 0
fi

if [[ ${1:-} == release && ${2:-} == download ]]; then
	asset=
	dir=
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dir)
			shift
			dir=${1:-}
			;;
		--pattern)
			shift
			asset=${1:-}
			;;
		esac
		shift
	done

	[[ -n $asset && -n $dir ]] || exit 2
	printf 'deb\n' > "$dir/$asset"
	exit 0
fi

exit 1
EOF
	cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$HOME"/package-log
exit 0
EOF
	cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == get-default ]]; then
	printf '%s\n' "${TILDE_FAKE_SYSTEMCTL:-multi-user.target}"
	exit 0
	fi

	exit 1
EOF
	chmod +x "$fake_bin/apt-get" "$fake_bin/brew" "$fake_bin/gh"
	chmod +x "$fake_bin/flatpak" "$fake_bin/sudo" "$fake_bin/systemctl"

	printf 'old link\n' >"$home/Dropbox/var/app/source-link.txt"
	printf 'old copy\n' >"$home/.config/sample/copy.txt"

	write_repo "$repo"
	write_private_repo "$private_repo"
	git -C "$repo" init -q
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	git -C "$repo" add .
	git -C "$repo" commit -q -m init
	git -C "$private_repo" init -q
	git -C "$private_repo" config user.email smoke@example.invalid
	git -C "$private_repo" config user.name Smoke
	git -C "$private_repo" add .
	git -C "$private_repo" commit -q -m init

	HOME=$home XDG_STATE_HOME=$state "$plan" --repo "$repo" --platform linux --host "$host" >"$plan_json"
	HOME=$home XDG_STATE_HOME=$state "$plan" --repo "$private_repo" --platform linux --host "$host" >"$private_plan_json"

	PLAN_JSON=$plan_json BAD_CONDITION_PLAN=$bad_condition_plan ruby -rjson -rdigest -e '
		def canonicalize(value)
			case value
			when Array
				value.map { |item| canonicalize(item) }
			when Hash
				value.keys.map(&:to_s).sort.to_h do |key|
					[key, canonicalize(value[key])]
				end
			else
				value
			end
		end

		plan = JSON.parse(File.read(ENV.fetch("PLAN_JSON")))
		action = plan.fetch("actions").find { |item| item.dig("package", "type") == "flatpak" }
		abort "missing flatpak action" unless action
		action.delete("condition")
		action.fetch("package")["condition"] = "headless"
		content = canonicalize(plan.reject { |key, _value| %w[generated_at plan_id].include?(key) })
		plan["plan_id"] = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(content))}"
		File.write(ENV.fetch("BAD_CONDITION_PLAN"), JSON.pretty_generate(plan))
	'

	cp -a "$repo" "$bad_repo"
	HOME=$home XDG_STATE_HOME=$state "$plan" --repo "$bad_repo" --platform linux --host "$host" >"$bad_plan"
	rm -f "$bad_repo/aaa-link/source.txt"

	if HOME=$home XDG_STATE_HOME=$state "$apply" --plan "$bad_plan" >"$tmpdir/bad.out" 2>"$bad_err"; then
		echo "expected validation failure to block apply" >&2
		exit 1
	fi
	grep -q "repository dirty state mismatch\\|source is not readable" "$bad_err"
	[[ ! -e $home/manual-ran ]]

	if HOME=$home XDG_STATE_HOME=$state "$apply" --plan "$bad_condition_plan" >"$tmpdir/bad-condition.out" 2>"$bad_condition_err"; then
		echo "expected unsupported nested condition to fail validation" >&2
		exit 1
	fi
	grep -q "unsupported condition: headless" "$bad_condition_err"

	mkdir -p "$state/tilde/hosts/$host"
	cat >"$state/tilde/hosts/$host/state.md" <<'EOF'
---
not a mapping
---
EOF

	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH TILDE_APPLY_STOP_AFTER=3 "$apply" \
		--plan "$private_plan_json" --plan "$plan_json" >"$tmpdir/partial.out"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH TILDE_FAKE_SYSTEMCTL=graphical.target "$apply" \
		--plan "$private_plan_json" --plan "$plan_json" >"$apply_json"

	[[ -L $home/Dropbox/var/app/source-link.txt ]]
	[[ $(readlink "$home/Dropbox/var/app/source-link.txt") == ../../src/home/aaa-link/source.txt ]]
	grep -q '^old link$' "$state"/tilde/hosts/"$host"/backups/*/Dropbox/var/app/source-link.txt
	grep -q '^copy$' "$home/.config/sample/copy.txt"
	grep -q '^old copy$' "$state"/tilde/hosts/"$host"/backups/*/.config/sample/copy.txt
	grep -q '^section$' "$home/section/created.txt"
	grep -q '^private$' "$home/.config/private/private.txt"
	grep -q '^flatpak ran$' "$home/flatpak-ran"
	[[ ! -e $home/manual-ran ]]
	[[ -f $state/tilde/hosts/$host/last-plan.json ]]
	[[ -f $state/tilde/hosts/$host/last-apply.json ]]
	[[ -f $state/tilde/hosts/$host/state.md ]]

	APPLY_JSON=$apply_json LAST_PLAN=$state/tilde/hosts/$host/last-plan.json STATE_FILE=$state/tilde/hosts/$host/state.md ruby -rjson -ryaml -e '
		apply = JSON.parse(File.read(ENV.fetch("APPLY_JSON")))
		abort "wrong apply schema" unless apply.fetch("schema") == "tilde.apply/v1"
		abort "apply should complete after resume" unless apply.fetch("completed")
		last_plan = JSON.parse(File.read(ENV.fetch("LAST_PLAN")))
		abort "wrong plan cache schema" unless last_plan.fetch("schema") == "tilde.cache/v1"
		abort "input id mismatch" unless last_plan.fetch("input_id") == apply.fetch("input_id")
		abort "last plan should combine public and private" unless last_plan.fetch("plans").length == 2
		abort "last plan should include private modules" unless last_plan.fetch("modules").any? { |mod| mod.fetch("id") == "private/zzz-private" }
		results = apply.fetch("results")
		abort "missing resumed action" unless results.any? { |result| result.fetch("diagnostics", {})["resumed"] }
		abort "flatpak should run after ignored partial result" unless results.any? { |result| result.fetch("module_id") == "public/flatpak" && result.fetch("status") == "ok" }
		abort "missing package failure" unless results.any? { |result| result.fetch("module_id") == "public/pkg" && result.fetch("status") == "notok" }
		abort "missing manual deferred result" unless results.any? { |result| result.fetch("module_id") == "public/manual" && result.fetch("status") == "deferred" }
		state, = File.read(ENV.fetch("STATE_FILE")).split(/^---\s*$/, 3)[1, 2]
		frontmatter = YAML.safe_load(state)
		abort "state should include public metadata" unless frontmatter.fetch("public").fetch("role") == "public"
		abort "state should include private metadata" unless frontmatter.fetch("private").fetch("role") == "private"
		abort "state should not invent bootstrap" if frontmatter.key?("bootstrap")
		done = frontmatter.fetch("done")
		abort "link module should be ok" unless done.fetch("public/aaa-link") == "ok"
		abort "flatpak module should be ok" unless done.fetch("public/flatpak") == "ok"
		abort "github module should be ok" unless done.fetch("public/github") == "ok"
		abort "manual module should be notok" unless done.fetch("public/manual") == "notok"
		abort "package module should be notok" unless done.fetch("public/pkg") == "notok"
		abort "private module should be ok" unless done.fetch("private/zzz-private") == "ok"
	'

	grep -q '^gh release view --repo owner/tool --json tagName,assets$' "$home/package-log"
	grep -q '^gh release download --repo owner/tool --pattern tool_1\.2\.3_linux_amd64\.deb --dir .*/tilde-github-.* --clobber$' "$home/package-log"
	grep -q '^sudo apt-get install -y .*/tool_1\.2\.3_linux_amd64\.deb$' "$home/package-log"

	STATE_FILE=$state/tilde/hosts/$host/state.md ruby -ryaml -rdate -e '
		path = ENV.fetch("STATE_FILE")
		_head, yaml, body = File.read(path).split(/^---\s*$\n?/, 3)
		frontmatter = YAML.safe_load(yaml, aliases: true, permitted_classes: [Date, Time])
		frontmatter["bootstrap"] = {
			"status" => "ok",
			"schema" => "tilde.bootstrap/v1",
			"platform" => "linux",
			"requirements" => "sha256:test",
			"checked_at" => "2026-01-01T00:00:00Z"
		}
		File.write(path, "---\n#{YAML.dump(frontmatter).delete_prefix("---\n")}---\n#{body}")
	'

	PLAN_JSON=$plan_json PRIVATE_PLAN_JSON=$private_plan_json SKIP_PLAN_JSON=$skip_plan_json SKIP_PRIVATE_PLAN_JSON=$skip_private_plan_json ruby -rjson -rdigest -e '
		def canonicalize(value)
			case value
			when Array
				value.map { |item| canonicalize(item) }
			when Hash
				value.keys.map(&:to_s).sort.to_h do |key|
					[key, canonicalize(value[key])]
				end
			else
				value
			end
		end

		def write_skip_plan(source, target)
			plan = JSON.parse(File.read(source))
			plan["actions"] = []
			plan.fetch("modules").each do |mod|
				mod["skipped"] = true
				mod["skip_reason"] = "already ok at current head"
				mod["packages_to_install"] = []
				mod["packages_to_refresh"] = []
				mod["packages_to_upgrade"] = []
				mod["links_to_create"] = []
				mod["copies_to_create"] = []
				mod["special_sections"] = {}
			end
			content = canonicalize(plan.reject { |key, _value| %w[generated_at plan_id].include?(key) })
			plan["plan_id"] = "sha256:#{Digest::SHA256.hexdigest(JSON.generate(content))}"
			File.write(target, JSON.pretty_generate(plan))
		end

		write_skip_plan(ENV.fetch("PLAN_JSON"), ENV.fetch("SKIP_PLAN_JSON"))
		write_skip_plan(ENV.fetch("PRIVATE_PLAN_JSON"), ENV.fetch("SKIP_PRIVATE_PLAN_JSON"))
	'

	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$apply" \
		--plan "$skip_private_plan_json" --plan "$skip_plan_json" >"$skip_apply_json"

	SKIP_APPLY_JSON=$skip_apply_json STATE_FILE=$state/tilde/hosts/$host/state.md ruby -rjson -ryaml -e '
		apply = JSON.parse(File.read(ENV.fetch("SKIP_APPLY_JSON")))
		abort "skip apply should complete" unless apply.fetch("completed")
		abort "skip apply should have no action results" unless apply.fetch("results").empty?
		state, = File.read(ENV.fetch("STATE_FILE")).split(/^---\s*$/, 3)[1, 2]
		frontmatter = YAML.safe_load(state)
		done = frontmatter.fetch("done")
		abort "bootstrap state should be preserved" unless frontmatter.fetch("bootstrap").fetch("status") == "ok"
		abort "skipped public ok module should be preserved" unless done.fetch("public/aaa-link") == "ok"
		abort "skipped public notok module should be preserved" unless done.fetch("public/pkg") == "notok"
		abort "skipped private module should be preserved" unless done.fetch("private/zzz-private") == "ok"
	'

	cp "$state/tilde/hosts/$host/state.md" "$state_before_refresh"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$plan" \
		--repo "$repo" --mode refresh --platform linux --host "$host" >"$refresh_plan_json"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$apply" \
		--plan "$refresh_plan_json" >"$refresh_apply_json"
	cmp -s "$state_before_refresh" "$state/tilde/hosts/$host/state.md"

	grep -q '^brew update$' "$home/package-log"
	grep -q '^brew upgrade$' "$home/package-log"
	grep -q '^sudo apt-get update$' "$home/package-log"
	grep -q '^sudo apt-get upgrade -y$' "$home/package-log"

	REFRESH_APPLY_JSON=$refresh_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("REFRESH_APPLY_JSON")))
		abort "refresh apply should complete" unless apply.fetch("completed")
		commands = apply.fetch("results").flat_map { |result| result.fetch("diagnostics", {}).fetch("commands", []) }
		abort "missing brew update diagnostics" unless commands.any? { |run| run.fetch("command") == %w[brew update] }
		abort "missing brew upgrade diagnostics" unless commands.any? { |run| run.fetch("command") == %w[brew upgrade] }
		abort "missing apt update diagnostics" unless commands.any? { |run| run.fetch("command") == %w[sudo apt-get update] }
		abort "missing apt upgrade diagnostics" unless commands.any? { |run| run.fetch("command") == %w[sudo apt-get upgrade -y] }
	'

	echo "apply smoke ok"
}

main "$@"
