#!/usr/bin/env bash

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
	[[ -z $cleanup_tmpdir ]] && return
	rm -rf "$cleanup_tmpdir" 2>/dev/null || {
		sleep 1
		rm -rf "$cleanup_tmpdir"
	}
}

commit_all() {
	local repo=$1
	local message=$2

	git -C "$repo" add .
	git -C "$repo" commit -q -m "$message"
}

pack() {
	local tilde=$1
	local repo=$2
	local bundle=$3
	shift 3

	rm -f "$bundle"
	"$tilde" checkout pack --repo "$repo" --bundle "$bundle" "$@"
}

write_private_repo() {
	local repo=$1

	mkdir -p "$repo"
	git -C "$repo" init -q
	git -C "$repo" checkout -q -B main
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	cat >"$repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: private
---

# Private
EOF
	printf 'one\n' >"$repo/value.txt"
	commit_all "$repo" init
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local bare
	local bad_trap
	local bundle
	local err
	local script_dir
	local skill_root
	local source
	local target
	local tilde
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	tilde=$skill_root/bin/tilde

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	bare=$tmpdir/home-.git
	bundle=$tmpdir/home-.bundle
	err=$tmpdir/checkout.err
	source=$tmpdir/source/home-
	target=$tmpdir/target/home-

	write_private_repo "$source"
	"$tilde" checkout pack --help | grep -q "checkout pack"
	"$tilde" checkout receive --help | grep -q "checkout receive"
	"$tilde" checkout remote --help | grep -q "checkout remote"
	git init -q --bare "$bare"
	git -C "$bare" symbolic-ref HEAD refs/heads/main
	git -C "$source" remote add origin "$bare"
	git -C "$source" push -q -u origin main

	pack "$tilde" "$source" "$bundle"
	"$tilde" checkout receive --repo "$target" --bundle "$bundle" --origin "$bare"
	grep -qx one "$target/value.txt"
	git -C "$target" rev-parse --abbrev-ref --symbolic-full-name '@{u}' | grep -qx origin/main
	if grep -nE '(^|[[:space:]])git bundle verify' "$skill_root/libexec/checkout"; then
		abort "bundle verify must run with repository context"
	fi
	bad_trap=$'\ttrap \'rm -f "$bundle"\' EXIT'
	if grep -Fxq "$bad_trap" "$skill_root/libexec/checkout"; then
		abort "bundle cleanup trap must not reference a local variable at process exit"
	fi

	printf 'two\n' >"$source/value.txt"
	commit_all "$source" update
	git -C "$source" push -q origin main
	pack "$tilde" "$source" "$bundle"
	"$tilde" checkout receive --repo "$target" --bundle "$bundle" --origin "$bare"
	grep -qx two "$target/value.txt"

	printf 'dirty\n' >"$target/dirty.txt"
	if "$tilde" checkout receive --repo "$target" --bundle "$bundle" --origin "$bare" >/dev/null 2>"$err"; then
		abort "expected dirty target to fail"
	fi
	grep -q "dirty repository" "$err"
	rm -f "$target/dirty.txt"

	printf 'three\n' >"$source/value.txt"
	commit_all "$source" unpushed
	if pack "$tilde" "$source" "$bundle" >/dev/null 2>"$err"; then
		abort "expected unpushed source to fail"
	fi
	grep -q "branch is not at upstream" "$err"

	pack "$tilde" "$source" "$bundle" --allow-unpushed
	"$tilde" checkout receive --repo "$target" --bundle "$bundle" --origin "$bare"
	grep -qx three "$target/value.txt"
}

main "$@"
