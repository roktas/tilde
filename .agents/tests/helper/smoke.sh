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
	local line_out
	local script_dir
	local skill_root
	local span_conflict
	local span_out
	local target
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	line_out=$tmpdir/line.jsonl
	span_conflict=$tmpdir/span-conflict.jsonl
	span_out=$tmpdir/span.jsonl
	target=$tmpdir/profile

	HOME=$tmpdir "$skill_root/bin/line" ensure "$target" 'export EDITOR=vim' >"$line_out"
	HOME=$tmpdir "$skill_root/bin/line" ensure "$target" 'export EDITOR=vim' >>"$line_out"
	HOME=$tmpdir "$skill_root/bin/line" remove "$target" 'export EDITOR=vim' >>"$line_out"
	[[ ! -s $target ]]

	LINE_OUT=$line_out ruby -rjson -e '
		statuses = File.readlines(ENV.fetch("LINE_OUT"), chomp: true).map { |line| JSON.parse(line).fetch("status") }
		abort "wrong line statuses" unless statuses == %w[changed unchanged removed]
	'

	HOME=$tmpdir "$skill_root/bin/span" ensure "$target" local-bin <<'EOF' >"$span_out"
export PATH="$HOME/.local/bin:$PATH"
EOF
	HOME=$tmpdir "$skill_root/bin/span" ensure "$target" local-bin <<'EOF' >>"$span_out"
export PATH="$HOME/.local/bin:$PATH"
EOF
	HOME=$tmpdir "$skill_root/bin/span" ensure "$target" local-bin --comment '#' <<'EOF' >>"$span_out"
export PATH="$HOME/bin:$PATH"
EOF
	grep -Fq 'export PATH="$HOME/bin:$PATH"' "$target"

	SPAN_OUT=$span_out ruby -rjson -e '
		statuses = File.readlines(ENV.fetch("SPAN_OUT"), chomp: true).map { |line| JSON.parse(line).fetch("status") }
		abort "wrong span statuses" unless statuses == %w[changed unchanged changed]
	'

	printf '# >>> tilde:bad\nx\n' >"$target"
	if printf 'x\n' | HOME=$tmpdir "$skill_root/bin/span" ensure "$target" bad >"$span_conflict" 2>/dev/null; then
		echo "expected malformed span conflict" >&2
		exit 1
	fi

	SPAN_CONFLICT=$span_conflict ruby -rjson -e '
		record = JSON.parse(File.read(ENV.fetch("SPAN_CONFLICT")))
		abort "wrong conflict status" unless record.fetch("status") == "conflict"
		abort "wrong conflict exit record" unless record.fetch("reason") == "malformed-marker"
	'

	echo "helper smoke ok"
}

main "$@"
