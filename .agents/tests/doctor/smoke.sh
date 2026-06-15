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

	mkdir -p "$repo"
	git -C "$repo" init -q
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	printf 'readme\n' >"$repo/README.md"
	git -C "$repo" add README.md
	git -C "$repo" commit -q -m init
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local home
	local host
	local out
	local public
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

	host=$(host_name)
	home=$tmpdir/home
	out=$tmpdir/doctor.json
	public=$home/Dropbox/home
	state=$tmpdir/state

	mkdir -p "$home/Dropbox" "$home/.agents/skills" "$state/tilde"
	write_repo "$public"
	printf 'entry\n' >"$home/Dropbox/AGENTS.md"
	ln -s "$home/Dropbox/AGENTS.md" "$home/AGENTS.md"
	ln -s missing "$home/.agents/skills/tilde"

	cat >"$state/tilde/state.yml" <<EOF
protocol: tilde/v1
public: $public
private: $home/Dropbox/home-
applied:
  level: normal
  platform: linux
  public: 0000000000000000000000000000000000000000
EOF

	HOME=$home XDG_STATE_HOME=$state "$tilde" doctor --format json --state-dir "$state/tilde" >"$out"

	DOCTOR_JSON=$out ruby -rjson -e '
		data = JSON.parse(File.read(ENV.fetch("DOCTOR_JSON")))
		abort "wrong schema" unless data.fetch("schema") == "tilde.doctor/v1"
		findings = data.fetch("findings")
		abort "doctor should not expose plan history" if data.key?("last_plan")
		abort "missing applied anchor finding" unless findings.any? { |item| item.fetch("kind") == "repository" && item.fetch("problems") == ["public repository differs from applied anchor"] }
		abort "missing private repository finding" unless findings.any? { |item| item.fetch("kind") == "repository" && item.fetch("problems") == ["private repository missing"] }
		by_target = findings.to_h { |item| [item.fetch("target"), item] }
		abort "home entrypoint should be host-absolute" unless by_target.fetch("~/AGENTS.md").fetch("problems") == ["host-absolute"]
		abort "tilde skill link should be broken" unless by_target.fetch("~/.agents/skills/tilde").fetch("problems") == ["broken"]
	'

	echo "doctor smoke ok"
}

main "$@"
