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
	local status
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	status=$skill_root/bin/status

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	host=$(host_name)
	home=$tmpdir/home
	state=$tmpdir/state
	out=$tmpdir/status.json

	mkdir -p "$home" "$state/tilde/hosts/$host"

	cat >"$state/tilde/hosts/$host/state.md" <<EOF
---
host: $host
date: 2026-06-05T00:00:00+03:00
done:
  public/app: ok
---
EOF

	cat >"$state/tilde/hosts/$host/last-plan.json" <<'EOF'
{
  "schema": "tilde.cache/v1",
  "generated_at": "2026-06-05T00:00:00+03:00",
  "core": {
    "home_entrypoints_to_write": [{"target": "~/AGENTS.md"}],
    "links_to_create": [{"target": "~/.agents"}]
  },
  "modules": [
    {
      "id": "public/app",
      "links_to_create": [{"target": "~/.config/app"}],
      "copies_to_create": [{"target": "~/.config/app/config"}],
      "packages_to_install": [{"name": "app"}],
      "packages_to_refresh": [{"name": "*"}],
      "packages_to_upgrade": [{"name": "*"}]
    }
  ]
}
EOF

	cat >"$state/tilde/hosts/$host/last-apply.json" <<'EOF'
{
  "schema": "tilde.apply/v1",
  "started_at": "2026-06-05T00:00:01+03:00",
  "completed": true,
  "results": [
    {"action_id": "public/app:link:config", "status": "ok"}
  ]
}
EOF

	HOME=$home XDG_STATE_HOME=$state "$status" --format json --state-dir "$state/tilde" >"$out"

	STATUS_JSON=$out ruby -rjson -e '
		data = JSON.parse(File.read(ENV.fetch("STATUS_JSON")))
		plan = data.fetch("caches").fetch("last_plan")
		apply = data.fetch("caches").fetch("last_apply")
		abort "wrong plan schema" unless plan.fetch("schema") == "tilde.cache/v1"
		abort "wrong module count" unless plan.fetch("module_count") == 1
		abort "wrong link count" unless plan.fetch("links") == 2
		abort "wrong copy count" unless plan.fetch("copies") == 1
		abort "wrong install package count" unless plan.fetch("install_packages") == 1
		abort "wrong refresh package count" unless plan.fetch("refresh_packages") == 1
		abort "wrong upgrade package count" unless plan.fetch("upgrade_packages") == 1
		abort "wrong apply schema" unless apply.fetch("schema") == "tilde.apply/v1"
		abort "apply should be complete" unless apply.fetch("completed")
		abort "wrong apply result count" unless apply.fetch("result_count") == 1
		abort "apply cache should not expose plan module count" if apply.key?("module_count")
	'

	echo "status smoke ok"
}

main "$@"
