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
	local help
	local script_dir
	local skill_root
	local status_help
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

	"$tilde" >"$help"
	grep -Fq 'Format: `$tilde <command> [<arguments>...]`' "$help"
	grep -Fq '| `status` | Show a short deployment, home-entrypoint, and managed-surface summary. |' "$help"

	"$tilde" .help status >"$status_help"
	grep -Fq '## `status`' "$status_help"

	"$tilde" boot --help >"$boot_help"
	grep -Fq 'Usage: bootstrap' "$boot_help"

	if "$tilde" deploy >/dev/null 2>"$deploy_err"; then
		echo "expected agent-orchestrated prompt command to fail as a runtime route" >&2
		exit 1
	fi
	grep -Fq 'no direct runtime route is defined' "$deploy_err"
}

main "$@"
