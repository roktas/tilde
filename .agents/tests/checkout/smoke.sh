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
	local link_target
	local script_dir
	local skill_root
	local source
	local replacement
	local runtime_source
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
	replacement=$tmpdir/source/replacement
	runtime_source=$tmpdir/runtime/source
	target=$tmpdir/target/home-
	link_target=$tmpdir/runtime/tilde

	write_private_repo "$source"
	"$tilde" checkout pack --help | grep -q "checkout pack"
	"$tilde" checkout receive --help | grep -q "checkout receive"
	"$tilde" checkout remote --help | grep -q "checkout remote"
	"$tilde" checkout runtime-link --help | grep -q "checkout runtime-link"
	git init -q --bare "$bare"
	git -C "$bare" symbolic-ref HEAD refs/heads/main
	git -C "$source" remote add origin "$bare"
	git -C "$source" push -q -u origin main

	pack "$tilde" "$source" "$bundle"
	mkdir -p "$target"
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

	write_private_repo "$replacement"
	printf 'replacement\n' >"$replacement/value.txt"
	commit_all "$replacement" replacement
	pack "$tilde" "$replacement" "$bundle" --allow-unpushed
	if "$tilde" checkout receive --repo "$target" --bundle "$bundle" --origin "$bare" >/dev/null 2>"$err"; then
		abort "expected divergent target to fail without replace-clean"
	fi
	grep -q "target cannot fast-forward" "$err"
	"$tilde" checkout receive --repo "$target" --bundle "$bundle" --origin "$bare" --replace-clean
	grep -qx replacement "$target/value.txt"

	git clone -q "$skill_root" "$runtime_source"
	git -C "$runtime_source" checkout -q "$(git -C "$skill_root" rev-parse HEAD)"
	git clone -q "$runtime_source" "$link_target"
	git -C "$link_target" checkout -q "$(git -C "$runtime_source" rev-parse HEAD)"
	git -C "$runtime_source" config user.email smoke@example.invalid
	git -C "$runtime_source" config user.name Smoke
	printf 'runtime source\n' >"$runtime_source/.runtime-source"
	git -C "$runtime_source" add .runtime-source
	git -C "$runtime_source" commit -q -m runtime-source
	"$tilde" checkout runtime-link --source "$runtime_source" --target "$link_target" --expected "$(git -C "$runtime_source" rev-parse HEAD)"
	[[ -L $link_target ]]
	[[ $(readlink "$link_target") == "$runtime_source" ]]
}

main "$@"
