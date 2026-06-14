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
	local markdown
	local out
	local script_dir
	local skill_root
	local state
	local tmpdir
	local tilde

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	tilde=$skill_root/bin/tilde

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	host=$(host_name)
	home=$tmpdir/home
	markdown=$tmpdir/status.md
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
  "mode": "apply",
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
      "packages_to_refresh": [],
      "packages_to_upgrade": []
    }
  ]
}
EOF

	cat >"$state/tilde/hosts/$host/last-apply.json" <<'EOF'
{
  "schema": "tilde.apply/v1",
  "started_at": "2026-06-05T00:00:01+03:00",
  "completed": true,
  "mode": "apply",
  "results": [
    {"action_id": "public/app:link:config", "status": "ok"}
  ]
}
EOF

	cat >"$state/tilde/hosts/$host/last-refresh-plan.json" <<'EOF'
{
  "schema": "tilde.cache/v1",
  "generated_at": "2026-06-05T00:00:02+03:00",
  "mode": "refresh",
  "core": {
    "home_entrypoints_to_write": [],
    "links_to_create": []
  },
  "modules": [
    {
      "id": "public/platform",
      "links_to_create": [],
      "copies_to_create": [],
      "packages_to_install": [],
      "packages_to_refresh": [{"name": "*"}],
      "packages_to_upgrade": []
    }
  ]
}
EOF

	cat >"$state/tilde/hosts/$host/last-refresh-apply.json" <<'EOF'
{
  "schema": "tilde.apply/v1",
  "started_at": "2026-06-05T00:00:03+03:00",
  "completed": true,
  "mode": "refresh",
  "results": [
    {"action_id": "public/platform:refresh:brew:*", "status": "ok"}
  ]
}
EOF

	HOME=$home XDG_STATE_HOME=$state "$tilde" status --format json --state-dir "$state/tilde" >"$out"
	HOME=$home XDG_STATE_HOME=$state "$tilde" status --format markdown --state-dir "$state/tilde" >"$markdown"

	STATUS_JSON=$out ruby -rjson -e '
		data = JSON.parse(File.read(ENV.fetch("STATUS_JSON")))
		plan = data.fetch("caches").fetch("last_plan")
		apply = data.fetch("caches").fetch("last_apply")
		refresh_plan = data.fetch("caches").fetch("last_refresh_plan")
		refresh_apply = data.fetch("caches").fetch("last_refresh_apply")
		abort "wrong plan schema" unless plan.fetch("schema") == "tilde.cache/v1"
		abort "wrong plan mode" unless plan.fetch("mode") == "apply"
		abort "wrong module count" unless plan.fetch("module_count") == 1
		abort "deployment fixture should not be partial" if plan.fetch("partial_surface")
		abort "wrong link count" unless plan.fetch("links") == 2
		abort "wrong copy count" unless plan.fetch("copies") == 1
		abort "wrong install package count" unless plan.fetch("install_packages") == 1
		abort "deployment plan should not include refresh packages" unless plan.fetch("refresh_packages") == 0
		abort "deployment plan should not include upgrade packages" unless plan.fetch("upgrade_packages") == 0
		abort "wrong refresh package count" unless refresh_plan.fetch("refresh_packages") == 1
		abort "wrong apply schema" unless apply.fetch("schema") == "tilde.apply/v1"
		abort "wrong apply mode" unless apply.fetch("mode") == "apply"
		abort "apply should be complete" unless apply.fetch("completed")
		abort "wrong apply result count" unless apply.fetch("result_count") == 1
		abort "wrong refresh apply mode" unless refresh_apply.fetch("mode") == "refresh"
		abort "wrong refresh apply result count" unless refresh_apply.fetch("result_count") == 1
		abort "apply cache should not expose plan module count" if apply.key?("module_count")
	'

	grep -Fq "Last deployment plan cache: present" "$markdown"
	grep -Fq "Last refresh plan cache: present" "$markdown"
	grep -Fq "Cached links: \`2\`" "$markdown"
	grep -Fq "Cached copies: \`1\`" "$markdown"
	grep -Fq "Cached refresh packages: \`1\`" "$markdown"

	echo "status smoke ok"
}

main "$@"
