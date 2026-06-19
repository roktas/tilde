#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail
[[ -z ${TRACE:-} ]] || set -x
unset CDPATH

cleanup_tmpdir=

abort() {
	warn "E: $*"
	exit 1
}

warn() {
	printf '%s\n' "$*" >&2
}

# ------------------------------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------------------------------

cleanup() {
	[[ -z $cleanup_tmpdir ]] || rm -rf "$cleanup_tmpdir"
}

assert_handoff_command() {
	local file=$1

	local command

	command=$(grep -m 1 '^ssh -t spinoza ' "$file" || true)
	[[ -n $command ]] || abort "missing remote handoff command in $file"
	[[ $command == *"sh -c"* ]] || abort "handoff command should use a POSIX shell payload"
	[[ $command == *'root="~/.agents/skills/tilde"'* ]] || abort "handoff command should target the default remote runtime root"
	[[ $command == *'sudo allow'* ]] || abort "handoff command should use the runtime when it exists"
	[[ $command == *'/etc/sudoers.d/tilde'* ]] || abort "handoff command should include a bootstrap sudoers fallback"
	[[ $command == *'visudo -cf'* ]] || abort "handoff command should validate the sudoers fallback"
	[[ $command != *"TILDE="* ]] || abort "handoff command should not require a TILDE assignment"

	bash -n -c "$command"
	if command -v zsh >/dev/null; then
		zsh -n -c "$command"
	fi
	if command -v fish >/dev/null; then
		fish -n -c "$command"
	fi
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local boot_help
	local checkout_err
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
	local ssh_err
	local script_dir
	local skill_root
	local status_help
	local sudo_alias_root
	local sudo_err
	local sudo_out
	local tilde
	local tmpdir
	local update_help
	local ssh_help

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	tilde=$skill_root/bin/tilde

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	help=$tmpdir/help.md
	status_help=$tmpdir/status-help.md
	boot_help=$tmpdir/boot-help.txt
	checkout_err=$tmpdir/checkout.err
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
	ssh_err=$tmpdir/ssh.err
	sudo_alias_root=$tmpdir/alias-root
	sudo_err=$tmpdir/sudo.err
	sudo_out=$tmpdir/sudo.out
	update_help=$tmpdir/update-help.md
	ssh_help=$tmpdir/ssh-help.md

	mkdir -p "$align_home" "$align_repo/config" "$align_repo/app" "$align_state/tilde" "$fake_bin" "$real_bin" "$sudo_alias_root/bin"
	cat >"$fake_bin/ssh" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$@" > "$TILDE_FAKE_SSH_ARGS"
cat > "$TILDE_FAKE_SSH_BODY"
if [ -n "${TILDE_FAKE_SSH_EXIT:-}" ]; then
	exit "$TILDE_FAKE_SSH_EXIT"
fi
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
	grep -Fq 'Prompt format: `/tilde <command> [<arguments>...]`' "$help"
	grep -Fq 'Do not execute `/tilde ...` or `$tilde ...` in a terminal.' "$help"
	grep -Fq '| `handoff` | `runtime` | Copy and print the privilege handoff command for the local or remote host. |' "$help"
	grep -Fq '| `status` | `runtime` | Show compact repository bindings and last fully converged anchors. |' "$help"
	grep -Fq '| `update` | `agent` | Run explicit update behavior from the current desired state. |' "$help"
	grep -Fq 'Runtime entrypoint: set `TILDE` to the loaded skill root `bin/tilde`; fallback `~/.agents/skills/tilde/bin/tilde`.' "$help"
	grep -Fq 'Do not search `PATH` after `tilde: command not found`; retry with `"$TILDE"`.' "$help"
	grep -Fq 'Target shorthand: omitted target means current host; bare `host` means `ssh:host` except when it names the current host; bare all-caps targets such as `ALL`, `HOME`, and `WORK` expand from the active home policy.' "$help"
	grep -Fq 'For defined host groups, report the expanded host list and continue; do not ask for permission to start the exact requested workflow.' "$help"
	grep -Fq 'When traversing a host group, skip hosts that fail a bounded noninteractive reachability check and continue with reachable hosts.' "$help"
	grep -Fq 'Run Tilde reachability probes through `"$TILDE" ssh`; do not use raw `ssh` for Tilde remote workflow probes.' "$help"
	grep -Fq 'For remote targets, generate plans and run live checks on the target host through Tilde SSH transport.' "$help"
	grep -Fq 'Write plan JSON files under a per-run `mktemp -d` directory and clean them with `trap`; do not leave fixed `/tmp/opencode/...` plan files.' "$help"
	grep -Fq 'Refresh/update mode does not advance `applied` anchors; report target HEAD separately from applied anchors.' "$help"
	grep -Fq 'After remote runtime freshness is verified, read target `tilde status --format json` and use `state.public` / `state.private` as plan repository bindings.' "$help"
	grep -Fq 'Bind remote plan repository paths to variables from target status JSON; do not retype host-convention paths in `plan --repo` commands.' "$help"
	grep -Fq 'Remote align uses target-local `plan --mode align` plus `apply`; do not run `tilde align --format json` on a remote target.' "$help"
	grep -Fq 'Do not redirect remote Tilde stderr to `/dev/null`; a non-zero remote exit means the step failed or deferred even when stdout is empty.' "$help"
	grep -Fq 'Remote script shell: default Tilde SSH uses POSIX `sh`; do not use Bash prelude, `pipefail`, `[[ ]]`, arrays, `source`, `local`, or `-- bash` for ordinary status, plan, apply, and verification scripts.' "$help"
	grep -Fq 'For mutating remote workflows, verify target runtime freshness before target status reads, plan, or apply; refresh stale Git-backed target checkouts first, or defer.' "$help"
	grep -Fq 'Runtime freshness checkout maps the loaded skill root to target `~/.agents/skills/tilde`; desired-state checkout maps the selected data repo to the target binding.' "$help"
	grep -Fq 'Remote freshness checkout route: use `"$TILDE" checkout remote --host HOST --repo CONTROLLER_REPO --target TARGET_REPO`; never call it with only `--host`.' "$help"
	grep -Fq 'For update targets with missing `state.yml` or no `applied` anchors, use `plan --mode repair` for state recovery instead of refresh; missing state is not proof the host was never deployed.' "$help"
	grep -Fq 'Status paths outside the `state.yml` model, such as `config.yml` or `hosts/HOST/state.md`, mean stale target runtime.' "$help"
	grep -Fq 'After successful mutating remote apply, run a final target status read and report target HEAD separately from applied anchors.' "$help"
	grep -Fq 'Do not read controller `~/.local/state/tilde/state.yml` for remote targets; target state lives on the target host.' "$help"

	"$tilde" .help status >"$status_help"
	grep -Fq '## `status`' "$status_help"
	grep -Fq 'Prompt: `/tilde status [host|ssh:<host>|GROUP]`' "$status_help"
	grep -Fq 'Remote note: deliver remote diagnostics through Tilde SSH transport; do not run target checks on the controller.' "$status_help"
	grep -Fq 'Remote state note: do not read controller `~/.local/state/tilde/state.yml`' "$status_help"
	"$tilde" .help update >"$update_help"
	grep -Fq 'Prompt: `/tilde update [host|ssh:<host>|GROUP] [full] [dry-run|plan-only]`' "$update_help"
	grep -Fq 'Remote freshness note: before target status reads that gate a mutating workflow, plan, or apply, verify target runtime freshness and refresh stale Git-backed target checkouts; defer if they cannot be safely refreshed.' "$update_help"
	grep -Fq 'State recovery note: if target status shows missing `state.yml` or no `applied` anchors, use `plan --mode repair`' "$update_help"
	grep -Fq 'Remote verification note: after successful mutating apply, run a final target status read before closeout.' "$update_help"
	"$tilde" help ssh >"$ssh_help"
	grep -Fq '`ssh` is an implementation route, not a public prompt command.' "$ssh_help"
	grep -Fq 'Runtime usage: `"$TILDE" ssh --help`' "$ssh_help"

	"$tilde" boot --help >"$boot_help"
	grep -Fq 'Usage: boot' "$boot_help"
	"$tilde" bootstrap --help >"$boot_help"
	grep -Fq 'Usage: boot' "$boot_help"
	"$tilde" align --help >"$align_help"
	grep -Fq 'Usage: "$TILDE" align' "$align_help"
	if "$tilde" align --format json >"$align_help" 2>&1; then
		abort "expected align --format to fail"
	fi
	grep -Fq 'align has no --format option' "$align_help"

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
	assert_handoff_command "$handoff"
	env -u WAYLAND_DISPLAY -u DISPLAY TILDE_FAKE_CLIPBOARD="$handoff_clipboard" PATH="$fake_bin:$PATH" \
		"$tilde" handoff --host spinoza >"$handoff"
	grep -Fq "Clipboard: copied with wl-copy." "$handoff"
	assert_handoff_command "$handoff_clipboard"

	if env -u TILDE_SUDO "$skill_root/bin/sudo" true >/dev/null 2>"$sudo_err"; then
		abort "expected sudo shim to fail outside Tilde execution"
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
	TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH "$tilde" ssh target -- bash <<'EOF'
printf 'bash\n'
EOF
	tr '\n' ' ' <"$ssh_args" | grep -Fq 'target bash -s -- '
	grep -Fq "printf 'bash\\n'" "$ssh_body"
	TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH "$tilde" ssh target <<'EOF'
printf 'rooted\n'
EOF
	grep -Fq 'TILDE_ROOT=${TILDE_ROOT:-"$HOME/.agents/skills/tilde"}' "$ssh_body"
	grep -Fq 'TILDE_SUDO=intercept' "$ssh_body"
	TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH \
		"$tilde" ssh -o BatchMode=yes -o ConnectTimeout=5 target <<'EOF'
printf 'options\n'
EOF
	tr '\n' ' ' <"$ssh_args" | grep -Fq -- '-o BatchMode=yes -o ConnectTimeout=5 target sh -s -- '
	if TILDE_FAKE_SSH_EXIT=7 TILDE_FAKE_SSH_ARGS=$ssh_args TILDE_FAKE_SSH_BODY=$ssh_body PATH=$fake_bin:$PATH \
		"$tilde" ssh target >/dev/null 2>"$ssh_err" <<'EOF'; then
printf 'fail\n'
EOF
		abort "expected ssh route to fail when remote script fails"
	fi
	grep -Fq 'E: remote script failed on target with exit 7' "$ssh_err"

	if "$tilde" checkout remote --host target >"$checkout_err" 2>&1; then
		abort "expected incomplete checkout remote command to fail"
	fi
	grep -Fq 'checkout remote requires --repo CONTROLLER_REPO and --target TARGET_REPO' "$checkout_err"

	if "$tilde" deploy >/dev/null 2>"$deploy_err"; then
		abort "expected agent-orchestrated prompt command to fail as a runtime route"
	fi
	grep -Fq 'no direct runtime route is defined' "$deploy_err"
}

main "$@"
