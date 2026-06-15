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

write_fake_bootstrap() {
	local home=$1

	mkdir -p \
		"$home/.linuxbrew/bin" \
		"$home/.linuxbrew/opt/curl/bin" \
		"$home/.linuxbrew/opt/git/bin" \
		"$home/.linuxbrew/opt/ruby/bin"

	cat >"$home/.linuxbrew/bin/brew" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
shellenv)
	printf 'export PATH="%s/.linuxbrew/bin:%s/.linuxbrew/opt/curl/bin:%s/.linuxbrew/opt/git/bin:%s/.linuxbrew/opt/ruby/bin:$PATH"\n' "$HOME" "$HOME" "$HOME" "$HOME"
	;;
--prefix)
	if [[ -n ${2:-} ]]; then
		printf '%s/.linuxbrew/opt/%s\n' "$HOME" "$2"
	else
		printf '%s/.linuxbrew\n' "$HOME"
	fi
	;;
update | install)
	exit 0
	;;
*)
	exit 0
	;;
esac
EOF

	cat >"$home/.linuxbrew/opt/curl/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl fake\n'
EOF
	cat >"$home/.linuxbrew/opt/git/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git fake\n'
EOF
	cat >"$home/.linuxbrew/opt/ruby/bin/ruby" <<'EOF'
#!/usr/bin/env bash
printf 'ruby fake\n'
EOF

	chmod +x \
		"$home/.linuxbrew/bin/brew" \
		"$home/.linuxbrew/opt/curl/bin/curl" \
		"$home/.linuxbrew/opt/git/bin/git" \
		"$home/.linuxbrew/opt/ruby/bin/ruby"
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local home
	local out
	local repo
	local script_dir
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
	out=$tmpdir/out
	repo=$tmpdir/repo
	state=$tmpdir/state

	mkdir -p "$home" "$repo" "$state"
	printf '# repo\n' >"$repo/README.md"
	git -C "$repo" init -q
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	git -C "$repo" add README.md
	git -C "$repo" commit -q -m init
	write_fake_bootstrap "$home"

	HOME=$home XDG_STATE_HOME=$state PATH=/usr/bin:/bin "$tilde" boot --check linux >"$out"
	grep -Fq "OK: bootstrap probe" "$out"
	[[ ! -e $state/tilde/hosts ]]
	[[ ! -e $state/tilde/state.yml ]]

	HOME=$home XDG_STATE_HOME=$state PATH=/usr/bin:/bin "$tilde" preflight --bootstrap check --require README.md "$repo" >"$out"
	grep -Fq "OK: $repo" "$out"
	[[ ! -e $state/tilde/hosts ]]
	[[ ! -e $state/tilde/state.yml ]]

	if HOME=$home XDG_STATE_HOME=$state "$tilde" preflight --bootstrap skip --require missing "$repo" >"$out" 2>&1; then
		echo "expected missing required path to fail" >&2
		exit 1
	fi
	grep -Fq "required checkout path is missing" "$out"

	echo "deploy smoke ok"
}

main "$@"
