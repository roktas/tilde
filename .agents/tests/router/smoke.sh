#!/usr/bin/env bash
# shellcheck disable=SC2016

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

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local boot_help
	local deploy_err
	local fake_bin
	local handoff
	local handoff_clipboard
	local help
	local align_help
	local align_home
	local align_out
	local align_repo
	local align_state
	local real_bin
	local ssh_args
	local ssh_body
	local script_dir
	local skill_root
	local status_help
	local sudo_alias_root
	local sudo_err
	local sudo_out
	local tilde
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	tilde=$skill_root/bin/tilde

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	help=$tmpdir/help.md
	status_help=$tmpdir/status-help.md
	boot_help=$tmpdir/boot-help.txt
	deploy_err=$tmpdir/deploy.err
	fake_bin=$tmpdir/bin
	handoff=$tmpdir/handoff.txt
	handoff_clipboard=$tmpdir/handoff.clipboard
	real_bin=$tmpdir/real-bin
	align_help=$tmpdir/align-help.txt
	align_home=$tmpdir/align-home
	align_out=$tmpdir/align.out
	align_repo=$tmpdir/align-repo
	align_state=$tmpdir/align-state
	ssh_args=$tmpdir/ssh.args
	ssh_body=$tmpdir/ssh.body
	sudo_alias_root=$tmpdir/alias-root
	sudo_err=$tmpdir/sudo.err
	sudo_out=$tmpdir/sudo.out

	mkdir -p "$align_home" "$align_repo/config" "$align_repo/app" "$align_state/tilde" "$fake_bin" "$real_bin" "$sudo_alias_root/bin"
	cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$@" > "$TILDE_FAKE_SSH_ARGS"
cat > "$TILDE_FAKE_SSH_BODY"
EOF
	cat >"$fake_bin/wl-copy" <<'EOF'
#!/usr/bin/env sh
cat > "$TILDE_FAKE_CLIPBOARD"
EOF
	cat >"$real_bin/sudo" <<'EOF'
#!/usr/bin/env sh
printf 'real sudo %s\n' "$*"
EOF
	cp "$skill_root/bin/sudo" "$sudo_alias_root/bin/sudo"
	chmod +x "$fake_bin/ssh" "$fake_bin/wl-copy" "$real_bin/sudo" "$sudo_alias_root/bin/sudo"

	[[ -x $skill_root/libexec/apply ]]
	[[ -x $skill_root/libexec/align ]]
	[[ -x $skill_root/libexec/boot ]]
	[[ -x $skill_root/libexec/handoff ]]
	[[ -x $skill_root/libexec/ssh ]]
	[[ -x $skill_root/libexec/sudo ]]

	"$tilde" >"$help"
	grep -Fq 'Format: `$tilde <command> [<arguments>...]`' "$help"
	grep -Fq '| `handoff` | `runtime` | Copy and print the privilege handoff command for the local or remote host. |' "$help"
	grep -Fq '| `status` | `runtime` | Show compact repository bindings and last fully converged anchors. |' "$help"
	grep -Fq '| `update` | `agent` | Run explicit update behavior from the current desired state. |' "$help"
	grep -Fq 'For remote targets, generate plans and run live checks on the target host through `tilde ssh HOST`.' "$help"
	grep -Fq 'Do not read controller `~/.local/state/tilde/state.yml` for remote targets; target state lives on the target host.' "$help"

	"$tilde" .help status >"$status_help"
	grep -Fq '## `status`' "$status_help"
	grep -Fq 'Remote state note: do not read controller `~/.local/state/tilde/state.yml`' "$status_help"

	"$tilde" boot --help >"$boot_help"
	grep -Fq 'Usage: boot' "$boot_help"
	"$tilde" bootstrap --help >"$boot_help"
	grep -Fq 'Usage: boot' "$boot_help"
	"$tilde" align --help >"$align_help"
	grep -Fq 'Usage: tilde align' "$align_help"

	cat >"$align_repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
---

# Align Smoke
EOF
	printf 'configured\n' >"$align_repo/config/app.conf"
	cat >"$align_repo/app/README.md" <<'EOF'
---
all:
  links:
    ../config/app.conf: ~/.config/app.conf
---

# App
EOF
	git -C "$align_repo" init -q
	git -C "$align_repo" config user.email smoke@example.invalid
	git -C "$align_repo" config user.name Smoke
	git -C "$align_repo" add .
	git -C "$align_repo" commit -q -m init
	HOME=$align_home XDG_STATE_HOME=$align_state "$tilde" align --repo "$align_repo" >"$align_out"
	[[ -L $align_home/.config/app.conf ]]
	grep -Fxq 'configured' "$align_home/.config/app.conf"
	[[ ! -f $align_state/tilde/state.yml ]]
	[[ -f $align_state/tilde/lock ]]

	"$tilde" sudo handoff --host spinoza --no-copy >"$handoff"
	grep -Fq "ssh -t 'spinoza' '\$HOME/.agents/skills/tilde/bin/tilde sudo allow'" "$handoff"
	TILDE_FAKE_CLIPBOARD=$handoff_clipboard WAYLAND_DISPLAY=wayland-1 PATH=$fake_bin:$PATH \
		"$tilde" handoff --host spinoza >"$handoff"
	grep -Fq "Clipboard: copied with wl-copy." "$handoff"
	grep -Fq "ssh -t 'spinoza' '\$HOME/.agents/skills/tilde/bin/tilde sudo allow'" "$handoff_clipboard"

	if env -u TILDE_SUDO "$skill_root/bin/sudo" true >/dev/null 2>"$sudo_err"; then
		echo "expected sudo shim to fail outside Tilde execution" >&2
		exit 1
	fi
	grep -Fq "Tilde sudo shim is only available" "$sudo_err"
	PATH=$sudo_alias_root/bin:$skill_root/bin:$real_bin:/usr/bin:/bin "$tilde" sudo -- true >"$sudo_out"
	grep -Fxq "real sudo -n true" "$sudo_out"
	PATH=$sudo_alias_root/bin:$skill_root/bin:$real_bin:/usr/bin:/bin "$tilde" sudo -- line ensure /tmp/tilde-line value >"$sudo_out"
	grep -Fq "real sudo -n env PATH=" "$sudo_out"
	grep -Fq "$skill_root/bin/line ensure /tmp/tilde-line value" "$sudo_out"

	TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH "$tilde" ssh --no-root target -- arg <<'EOF'
printf 'remote\n'
EOF
	tr '\n' ' ' <"$ssh_args" | grep -Fq 'target sh -s -- arg '
	grep -Fq 'LC_ALL=en_US.UTF-8' "$ssh_body"
	grep -Fq 'LANG=en_US.UTF-8' "$ssh_body"
	grep -Fq 'PATH="/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"' "$ssh_body"
	grep -Fq "printf 'remote\\n'" "$ssh_body"
	TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH "$tilde" ssh target <<'EOF'
printf 'rooted\n'
EOF
	grep -Fq 'TILDE_ROOT=${TILDE_ROOT:-"$HOME/.agents/skills/tilde"}' "$ssh_body"
	grep -Fq 'TILDE_SUDO=intercept' "$ssh_body"

	if "$tilde" deploy >/dev/null 2>"$deploy_err"; then
		echo "expected agent-orchestrated prompt command to fail as a runtime route" >&2
		exit 1
	fi
	grep -Fq 'no direct runtime route is defined' "$deploy_err"
}

main "$@"
