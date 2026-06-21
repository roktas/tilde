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
	local head
	local home
	local host
	local markdown
	local repair_shell
	local out
	local public
	local shell
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
	markdown=$tmpdir/status.md
	out=$tmpdir/status.json
	public=$home/Dropbox/home
	repair_shell=$tmpdir/status-repair.sh
	shell=$tmpdir/status.sh
	state=$tmpdir/state

	mkdir -p "$home/Dropbox" "$state/tilde"
	write_repo "$public"
	head=$(git -C "$public" rev-parse HEAD)

	cat >"$state/tilde/state.yml" <<EOF
protocol: tilde/v1
skill: $skill_root
public: $public
applied:
  level: minimal
  platform: linux
  public: $head
EOF

	HOME=$home XDG_STATE_HOME=$state "$tilde" status --format json --state-dir "$state/tilde" >"$out"
	HOME=$home XDG_STATE_HOME=$state "$tilde" status --format markdown --state-dir "$state/tilde" >"$markdown"
	HOME=$home XDG_STATE_HOME=$state "$tilde" status --format shell --state-dir "$state/tilde" >"$shell"

	STATUS_JSON=$out ruby -rjson -e '
		data = JSON.parse(File.read(ENV.fetch("STATUS_JSON")))
		state = data.fetch("state")
		abort "state should be present" unless state.fetch("present")
		abort "wrong protocol" unless state.fetch("protocol") == "tilde/v1"
		abort "wrong applied level" unless state.fetch("applied").fetch("level") == "minimal"
		abort "status must not expose caches" if data.key?("caches")
		public = data.fetch("repositories").fetch("public")
		abort "public repo should exist" unless public.fetch("exists")
		abort "public repo should be clean" if public.fetch("dirty")
		private = data.fetch("repositories").fetch("private")
		abort "private repo should be unconfigured" if private["path"]
	'

	grep -Fq "State: present" "$markdown"
	grep -Fq "Applied level: \`minimal\`" "$markdown"
	grep -Fq "Fast status does not read module READMEs" "$markdown"

	# shellcheck disable=SC1090
	. "$shell"
	[[ ${tilde_host:-} = "$host" ]]
	[[ ${tilde_state_present:-} = true ]]
	[[ ${tilde_state_has_applied:-} = true ]]
	[[ ${tilde_update_mode:-} = refresh ]]
	[[ ${tilde_public_repo:-} = "$public" ]]
	[[ ${tilde_private_repo:-} = "" ]]
	[[ ${tilde_level:-} = minimal ]]
	[[ ${tilde_platform:-} = linux ]]
	[[ ${tilde_applied_public:-} = "$head" ]]
	[[ ${tilde_public_head:-} = "${head:0:7}" ]]

	cat >"$state/tilde/state.yml" <<EOF
protocol: tilde/v1
skill: $skill_root
public: $public
EOF

	HOME=$home XDG_STATE_HOME=$state "$tilde" status --format shell --state-dir "$state/tilde" >"$repair_shell"
	# shellcheck disable=SC1090
	. "$repair_shell"
	[[ ${tilde_state_present:-} = true ]]
	[[ ${tilde_state_has_applied:-} = false ]]
	[[ ${tilde_update_mode:-} = repair ]]
	[[ ${tilde_level:-} = normal ]]
	[[ ${tilde_public_repo:-} = "$public" ]]

	echo "status smoke ok"
}

main "$@"
