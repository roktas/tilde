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
	local bad_plan
	local bad_repo
	local fake_bin
	local home
	local host
	local plan
	local plan_json
	local private_plan_json
	local private_repo
	local repo
	local script_dir
	local skill_root
	local state
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
	bad_plan=$tmpdir/bad-plan.json
	apply_json=$tmpdir/apply.json
	bad_err=$tmpdir/bad.err

	mkdir -p \
		"$fake_bin" \
		"$home/Dropbox/var/app" \
		"$home/.config/sample" \
		"$private_repo" \
		"$repo" \
		"$state/tilde/hosts/$host"

	cat >"$fake_bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'fake brew failure\n' >&2
exit 7
EOF
	cat >"$fake_bin/flatpak" <<'EOF'
#!/usr/bin/env bash
printf 'flatpak ran\n' > "$HOME"/flatpak-ran
exit 9
EOF
	cat >"$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == get-default ]]; then
	printf 'multi-user.target\n'
	exit 0
fi

exit 1
EOF
	chmod +x "$fake_bin/brew"
	chmod +x "$fake_bin/flatpak" "$fake_bin/systemctl"

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

	cp -a "$repo" "$bad_repo"
	HOME=$home XDG_STATE_HOME=$state "$plan" --repo "$bad_repo" --platform linux --host "$host" >"$bad_plan"
	rm -f "$bad_repo/aaa-link/source.txt"

	if HOME=$home XDG_STATE_HOME=$state "$apply" --plan "$bad_plan" >"$tmpdir/bad.out" 2>"$bad_err"; then
		echo "expected validation failure to block apply" >&2
		exit 1
	fi
	grep -q "repository dirty state mismatch\\|source is not readable" "$bad_err"
	[[ ! -e $home/manual-ran ]]

	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:/usr/bin:/bin TILDE_APPLY_STOP_AFTER=1 "$apply" \
		--plan "$private_plan_json" --plan "$plan_json" >"$tmpdir/partial.out"
	HOME=$home XDG_STATE_HOME=$state PATH=$fake_bin:/usr/bin:/bin "$apply" \
		--plan "$private_plan_json" --plan "$plan_json" >"$apply_json"

	[[ -L $home/Dropbox/var/app/source-link.txt ]]
	[[ $(readlink "$home/Dropbox/var/app/source-link.txt") == ../../src/home/aaa-link/source.txt ]]
	grep -q '^old link$' "$state"/tilde/hosts/"$host"/backups/*/Dropbox/var/app/source-link.txt
	grep -q '^copy$' "$home/.config/sample/copy.txt"
	grep -q '^old copy$' "$state"/tilde/hosts/"$host"/backups/*/.config/sample/copy.txt
	grep -q '^section$' "$home/section/created.txt"
	grep -q '^private$' "$home/.config/private/private.txt"
	[[ ! -e $home/flatpak-ran ]]
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
		abort "missing ignored flatpak result" unless results.any? { |result| result.fetch("module_id") == "public/flatpak" && result.fetch("status") == "ignored" && result.fetch("diagnostics", {}).fetch("reason") == "condition not met: graphical" }
		abort "missing package failure" unless results.any? { |result| result.fetch("module_id") == "public/pkg" && result.fetch("status") == "notok" }
		abort "missing manual deferred result" unless results.any? { |result| result.fetch("module_id") == "public/manual" && result.fetch("status") == "deferred" }
		state, = File.read(ENV.fetch("STATE_FILE")).split(/^---\s*$/, 3)[1, 2]
		frontmatter = YAML.safe_load(state)
		abort "state should include public metadata" unless frontmatter.fetch("public").fetch("role") == "public"
		abort "state should include private metadata" unless frontmatter.fetch("private").fetch("role") == "private"
		done = frontmatter.fetch("done")
		abort "link module should be ok" unless done.fetch("public/aaa-link") == "ok"
		abort "flatpak module should be ok" unless done.fetch("public/flatpak") == "ok"
		abort "manual module should be notok" unless done.fetch("public/manual") == "notok"
		abort "package module should be notok" unless done.fetch("public/pkg") == "notok"
		abort "private module should be ok" unless done.fetch("private/zzz-private") == "ok"
	'

	echo "apply smoke ok"
}

main "$@"
