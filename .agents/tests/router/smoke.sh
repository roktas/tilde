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
	local help
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
	real_bin=$tmpdir/real-bin
	ssh_args=$tmpdir/ssh.args
	ssh_body=$tmpdir/ssh.body
	sudo_alias_root=$tmpdir/alias-root
	sudo_err=$tmpdir/sudo.err
	sudo_out=$tmpdir/sudo.out

	mkdir -p "$fake_bin" "$real_bin" "$sudo_alias_root/bin"
	cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$@" > "$TILDE_FAKE_SSH_ARGS"
cat > "$TILDE_FAKE_SSH_BODY"
EOF
	cat >"$real_bin/sudo" <<'EOF'
#!/usr/bin/env sh
printf 'real sudo %s\n' "$*"
EOF
	cp "$skill_root/bin/sudo" "$sudo_alias_root/bin/sudo"
	chmod +x "$fake_bin/ssh" "$real_bin/sudo" "$sudo_alias_root/bin/sudo"

	[[ -x $skill_root/libexec/apply ]]
	[[ -x $skill_root/libexec/boot ]]
	[[ -x $skill_root/libexec/ssh ]]
	[[ -x $skill_root/libexec/sudo ]]

	"$tilde" >"$help"
	grep -Fq 'Format: `$tilde <command> [<arguments>...]`' "$help"
	grep -Fq '| `status` | Show a short deployment, home-entrypoint, and managed-surface summary. |' "$help"

	"$tilde" .help status >"$status_help"
	grep -Fq '## `status`' "$status_help"

	"$tilde" boot --help >"$boot_help"
	grep -Fq 'Usage: boot' "$boot_help"
	"$tilde" bootstrap --help >"$boot_help"
	grep -Fq 'Usage: boot' "$boot_help"

	"$tilde" sudo handoff --host spinoza >"$handoff"
	grep -Fq "ssh -t 'spinoza' '\$HOME/.agents/skills/tilde/bin/tilde sudo allow'" "$handoff"

	if env -u TILDE_SUDO "$skill_root/bin/sudo" true >/dev/null 2>"$sudo_err"; then
		echo "expected sudo shim to fail outside Tilde execution" >&2
		exit 1
	fi
	grep -Fq "Tilde sudo shim is only available" "$sudo_err"
	PATH=$sudo_alias_root/bin:$skill_root/bin:$real_bin:/usr/bin:/bin "$tilde" sudo -- true >"$sudo_out"
	grep -Fxq "real sudo -n true" "$sudo_out"

	TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH "$tilde" ssh --no-root target -- arg <<'EOF'
printf 'remote\n'
EOF
	tr '\n' ' ' <"$ssh_args" | grep -Fq 'target sh -s -- arg '
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
