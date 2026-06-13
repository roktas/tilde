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
		"$repo/missing-command" \
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

```text
printf 'manual\n' > "$HOME"/manual-ran
```
EOF

	cat >"$repo/missing-command/README.md" <<'EOF'
---
all:
  packages:
    - scoop:missing
  links:
    configured.txt: ~/.config/missing-command/configured.txt
---

# Missing Command
EOF
	printf 'configured\n' >"$repo/missing-command/configured.txt"

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

Document the executable section before the shell block.

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

write_privilege_repo() {
	local repo=$1

	mkdir -p "$repo/sudo-section"

	cat >"$repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
---

# Privilege Apply Smoke
EOF

	cat >"$repo/sudo-section/README.md" <<'EOF'
# Sudo Section

## Install

This block keeps running after sudo so the executor must read the Tilde sudo event log.

```bash
sudo -n true || true
printf 'after sudo\n' > "$HOME"/sudo-swallowed
```
EOF
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local align_apply_json
	local align_home
	local align_plan_json
	local align_state
	local apply
	local apply_before_refresh
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
	local plan_before_refresh
	local plan_json
	local private_plan_json
	local private_repo
	local privilege_apply_json
	local privilege_home
	local privilege_plan_json
	local privilege_repo
	local privilege_state
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
	align_home=$tmpdir/align-home
	align_state=$tmpdir/align-state
	home=$tmpdir/home
	state=$tmpdir/state
	repo=$home/Dropbox/src/home
	private_repo=$home/Dropbox/src/home-
	privilege_apply_json=$tmpdir/privilege-apply.json
	privilege_home=$tmpdir/privilege-home
	privilege_plan_json=$tmpdir/privilege-plan.json
	privilege_repo=$privilege_home/Dropbox/src/home
	privilege_state=$tmpdir/privilege-state
	bad_repo=$tmpdir/bad-home
	fake_bin=$tmpdir/bin
	apply_before_refresh=$tmpdir/apply-before-refresh.json
	align_apply_json=$tmpdir/align-apply.json
	align_plan_json=$tmpdir/align-plan.json
	plan_json=$tmpdir/plan.json
	plan_before_refresh=$tmpdir/plan-before-refresh.json
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
		"$align_home" \
		"$fake_bin" \
		"$home/Dropbox/var/app" \
		"$home/.config/sample" \
		"$privilege_repo" \
		"$privilege_state/tilde" \
		"$private_repo" \
		"$repo" \
		"$align_state/tilde" \
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
if [[ ${TILDE_FAKE_SUDO:-} == auth ]]; then
	printf 'sudo: a password is required\n' >&2
	exit 1
fi

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
	write_privilege_repo "$privilege_repo"
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
	git -C "$privilege_repo" init -q
	git -C "$privilege_repo" config user.email smoke@example.invalid
	git -C "$privilege_repo" config user.name Smoke
	git -C "$privilege_repo" add .
	git -C "$privilege_repo" commit -q -m init

	HOME=$home XDG_STATE_HOME=$state "$plan" --repo "$repo" --platform linux --host "$host" >"$plan_json"
	HOME=$home XDG_STATE_HOME=$state "$plan" --repo "$private_repo" --platform linux --host "$host" >"$private_plan_json"
	HOME=$privilege_home XDG_STATE_HOME=$privilege_state "$plan" --repo "$privilege_repo" --platform linux --host "$host" >"$privilege_plan_json"
	HOME=$privilege_home XDG_STATE_HOME=$privilege_state PATH=$fake_bin:$PATH TILDE_FAKE_SUDO=auth "$apply" \
		--plan "$privilege_plan_json" >"$privilege_apply_json"
	grep -q '^after sudo$' "$privilege_home/sudo-swallowed"
	PRIVILEGE_APPLY_JSON=$privilege_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("PRIVILEGE_APPLY_JSON")))
		result = apply.fetch("results").find { |item| item.fetch("module_id") == "public/sudo-section" }
		abort "missing sudo-section result" unless result
		abort "sudo-section should defer" unless result.fetch("status") == "deferred"
		abort "missing privilege reason" unless result.fetch("diagnostics").fetch("reason") == "privilege required"
		sudo = result.fetch("diagnostics").fetch("blocks").flat_map { |block| block.fetch("sudo", []) }
		abort "missing sudo event" unless sudo.any? { |event| event.fetch("event") == "privilege_required" }
	'
	HOME=$align_home XDG_STATE_HOME=$align_state "$plan" --repo "$repo" --mode align --platform linux --host "$host" >"$align_plan_json"
	HOME=$align_home XDG_STATE_HOME=$align_state PATH=/usr/bin:/bin "$apply" --plan "$align_plan_json" >"$align_apply_json"
	[[ -L $align_home/Dropbox/var/app/source-link.txt ]]
	grep -q '^copy$' "$align_home/.config/sample/copy.txt"
	grep -q '^configured$' "$align_home/.config/missing-command/configured.txt"
	[[ -f $align_state/tilde/hosts/$host/last-align-plan.json ]]
	[[ -f $align_state/tilde/hosts/$host/last-align-apply.json ]]
	[[ ! -f $align_state/tilde/hosts/$host/state.md ]]

	ALIGN_APPLY_JSON=$align_apply_json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("ALIGN_APPLY_JSON")))
		abort "align apply should complete" unless apply.fetch("completed")
		abort "wrong align mode" unless apply.fetch("mode") == "align"
		abort "align should not run packages" if apply.fetch("results").any? { |result| result.fetch("kind") == "package" }
		abort "align should not run sections" if apply.fetch("results").any? { |result| %w[section manual].include?(result.fetch("kind")) }
	'

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
	grep -q '^configured$' "$home/.config/missing-command/configured.txt"
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
		abort "missing command package should defer" unless results.any? { |result| result.fetch("module_id") == "public/missing-command" && result.fetch("status") == "deferred" }
		abort "missing package failure" unless results.any? { |result| result.fetch("module_id") == "public/pkg" && result.fetch("status") == "notok" }
		manual = results.find { |result| result.fetch("module_id") == "public/manual" }
		abort "missing manual deferred result" unless manual&.fetch("status") == "deferred"
		abort "manual reason should identify non-shell code" unless manual.fetch("diagnostics").fetch("reason") == "non-shell-code"
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
		abort "missing command module should be notok" unless done.fetch("public/missing-command") == "notok"
		abort "package module should be notok" unless done.fetch("public/pkg") == "notok"
		abort "private module should be ok" unless done.fetch("private/zzz-private") == "ok"
	'

	grep -q '^gh release view --repo owner/tool --json tagName,assets$' "$home/package-log"
	grep -q '^gh release download --repo owner/tool --pattern tool_1\.2\.3_linux_amd64\.deb --dir .*/tilde-github-.* --clobber$' "$home/package-log"
	grep -q '^sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y .*/tool_1\.2\.3_linux_amd64\.deb$' "$home/package-log"

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

	SKIP_APPLY_JSON=$skip_apply_json LAST_PLAN=$state/tilde/hosts/$host/last-plan.json STATE_FILE=$state/tilde/hosts/$host/state.md ruby -rjson -ryaml -e '
		apply = JSON.parse(File.read(ENV.fetch("SKIP_APPLY_JSON")))
		last_plan = JSON.parse(File.read(ENV.fetch("LAST_PLAN")))
		abort "skip apply should complete" unless apply.fetch("completed")
		abort "skip apply should have no action results" unless apply.fetch("results").empty?
		abort "skip apply should preserve cached link actions" unless last_plan.fetch("actions").any? { |action| action.fetch("kind") == "link" }
		abort "skip apply should preserve cached module links" unless last_plan.fetch("modules").any? { |mod| mod.fetch("links_to_create", []).any? }
		state, = File.read(ENV.fetch("STATE_FILE")).split(/^---\s*$/, 3)[1, 2]
		frontmatter = YAML.safe_load(state)
		done = frontmatter.fetch("done")
		abort "bootstrap state should be preserved" unless frontmatter.fetch("bootstrap").fetch("status") == "ok"
		abort "skipped public ok module should be preserved" unless done.fetch("public/aaa-link") == "ok"
		abort "skipped public notok module should be preserved" unless done.fetch("public/pkg") == "notok"
		abort "skipped private module should be preserved" unless done.fetch("private/zzz-private") == "ok"
	'

	cp "$state/tilde/hosts/$host/state.md" "$state_before_refresh"
	cp "$state/tilde/hosts/$host/last-plan.json" "$plan_before_refresh"
	cp "$state/tilde/hosts/$host/last-apply.json" "$apply_before_refresh"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$plan" \
		--repo "$repo" --mode refresh --platform linux --host "$host" >"$refresh_plan_json"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:$PATH "$apply" \
		--plan "$refresh_plan_json" >"$refresh_apply_json"
	cmp -s "$state_before_refresh" "$state/tilde/hosts/$host/state.md"
	cmp -s "$plan_before_refresh" "$state/tilde/hosts/$host/last-plan.json"
	cmp -s "$apply_before_refresh" "$state/tilde/hosts/$host/last-apply.json"
	[[ -f $state/tilde/hosts/$host/last-refresh-plan.json ]]
	[[ -f $state/tilde/hosts/$host/last-refresh-apply.json ]]

	grep -q '^brew update$' "$home/package-log"
	grep -q '^brew upgrade$' "$home/package-log"
	grep -q '^sudo -n env DEBIAN_FRONTEND=noninteractive apt-get update$' "$home/package-log"
	grep -q '^sudo -n env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y$' "$home/package-log"

	REFRESH_APPLY_JSON=$refresh_apply_json REFRESH_APPLY_CACHE=$state/tilde/hosts/$host/last-refresh-apply.json REFRESH_PLAN_CACHE=$state/tilde/hosts/$host/last-refresh-plan.json ruby -rjson -e '
		apply = JSON.parse(File.read(ENV.fetch("REFRESH_APPLY_JSON")))
		apply_cache = JSON.parse(File.read(ENV.fetch("REFRESH_APPLY_CACHE")))
		plan_cache = JSON.parse(File.read(ENV.fetch("REFRESH_PLAN_CACHE")))
		abort "refresh apply should complete" unless apply.fetch("completed")
		abort "refresh apply cache should complete" unless apply_cache.fetch("completed")
		abort "wrong refresh apply mode" unless apply_cache.fetch("mode") == "refresh"
		abort "wrong refresh plan mode" unless plan_cache.fetch("mode") == "refresh"
		commands = apply.fetch("results").flat_map { |result| result.fetch("diagnostics", {}).fetch("commands", []) }
		abort "missing brew update diagnostics" unless commands.any? { |run| run.fetch("command") == %w[brew update] }
		abort "missing brew upgrade diagnostics" unless commands.any? { |run| run.fetch("command") == %w[brew upgrade] }
		abort "missing apt update diagnostics" unless commands.any? { |run| run.fetch("command") == %w[sudo -n env DEBIAN_FRONTEND=noninteractive apt-get update] }
		abort "missing apt upgrade diagnostics" unless commands.any? { |run| run.fetch("command") == %w[sudo -n env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y] }
	'

	echo "apply smoke ok"
}

main "$@"
