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

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local home
	local host
	local out
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
	state=$tmpdir/state
	out=$tmpdir/doctor.json

	mkdir -p \
		"$home/Dropbox/.dropbox.cache" \
		"$home/Dropbox/.tmp" \
		"$home/Dropbox/allos/bin" \
		"$home/Dropbox/archive" \
		"$home/Dropbox/home/bin" \
		"$state/tilde/hosts/$host"

	printf 'tool\n' >"$home/Dropbox/home/bin/tool"
	ln -s "$home/Dropbox/home/bin/tool" "$home/Dropbox/allos/bin/tool"
	ln -s "$home/Dropbox/missing" "$home/Dropbox/.dropbox.cache/broken"
	ln -s "$home/Dropbox/home/bin/tool" "$home/Dropbox/archive/tool"
	ln -s ../home/bin/tool "$home/Dropbox/.tmp/tool"

	cat >"$state/tilde/hosts/$host/last-plan.json" <<EOF
{
  "schema": "tilde.cache/v1",
  "actions": [
    {"id": "public/allos:link:tool", "kind": "link", "module_id": "public/allos", "target": "~/Dropbox/allos/bin/tool"},
    {"id": "public/cache:link:broken", "kind": "link", "module_id": "public/cache", "target": "~/Dropbox/.dropbox.cache/broken"},
    {"id": "public/archive:link:tool", "kind": "link", "module_id": "public/archive", "target": "~/Dropbox/archive/tool"},
    {"id": "public/tmp:link:tool", "kind": "link", "module_id": "public/tmp", "target": "~/Dropbox/.tmp/tool"},
    {"id": "public/config:link:file", "kind": "link", "module_id": "public/config", "target": "~/.config/file"}
  ]
}
EOF

	HOME=$home XDG_STATE_HOME=$state "$tilde" doctor --format json --state-dir "$state/tilde" >"$out"

	DOCTOR_JSON=$out ruby -rjson -e '
		data = JSON.parse(File.read(ENV.fetch("DOCTOR_JSON")))
		abort "wrong schema" unless data.fetch("schema") == "tilde.doctor/v1"
		findings = data.fetch("findings")
		abort "wrong finding count" unless findings.length == 5
		abort "missing config health finding" unless findings.any? { |item| item.fetch("kind") == "state" && item.fetch("problems") == ["missing config"] }
		abort "missing host state health finding" unless findings.any? { |item| item.fetch("kind") == "state" && item.fetch("problems") == ["missing host state"] }
		by_target = findings.to_h { |item| [item.fetch("target"), item] }
		abort "active link should be host-absolute" unless by_target.fetch("~/Dropbox/allos/bin/tool").fetch("problems") == ["host-absolute"]
		abort "active link should be active" unless by_target.fetch("~/Dropbox/allos/bin/tool").fetch("area") == "active"
		abort "cache link should be broken and host-absolute" unless by_target.fetch("~/Dropbox/.dropbox.cache/broken").fetch("problems") == ["broken", "host-absolute"]
		abort "cache link should be cache" unless by_target.fetch("~/Dropbox/.dropbox.cache/broken").fetch("area") == "cache"
		abort "archive link should be archive" unless by_target.fetch("~/Dropbox/archive/tool").fetch("area") == "archive"
		abort "tmp relative link should not be reported" if by_target.key?("~/Dropbox/.tmp/tool")
		abort "non-Dropbox link should not be reported" if by_target.key?("~/.config/file")
	'

	echo "doctor smoke ok"
}

main "$@"
