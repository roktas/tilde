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

platform_name() {
	case $(uname -s) in
	Darwin)
		printf 'macos\n'
		;;
	Linux)
		printf 'linux\n'
		;;
	*)
		printf 'unknown\n'
		;;
	esac
}

write_bootstrap_state() {
	local home=$1
	local platform=$2

	local host

	host=$(host_name)
	mkdir -p "$home/.local/state/tilde/hosts/$host"
	cat >"$home/.local/state/tilde/hosts/$host/state.md" <<EOF
---
host: $host
bootstrap:
  status: ok
  schema: tilde.bootstrap/v1
  platform: $platform
  requirements: sha256:18ed5cbd4623dd0e94850f4d911130f93b5eff6286fd1d47815738832cc7b992
---
EOF
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local auto_home
	local bootstrap
	local bootstrap_bin
	local bootstrap_home
	local bootstrap_out
	local cold_bin
	local cold_home
	local err
	local fake_bin
	local object
	local preflight
	local repo
	local script_dir
	local skill_root
	local tree
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	bootstrap=$skill_root/bin/bootstrap
	preflight=$skill_root/bin/preflight

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	trap cleanup EXIT HUP INT QUIT TERM

	err=$tmpdir/preflight.err
	auto_home=$tmpdir/auto-home
	cold_bin=$tmpdir/cold-bin
	cold_home=$tmpdir/cold-home
	fake_bin=$tmpdir/bin
	repo=$tmpdir/repo
	bootstrap_bin=$tmpdir/bootstrap-bin
	bootstrap_home=$tmpdir/home
	bootstrap_out=$tmpdir/bootstrap.out

	mkdir -p \
		"$auto_home" \
		"$bootstrap_bin" \
		"$bootstrap_home/.linuxbrew/bin" \
		"$bootstrap_home/.linuxbrew/opt/curl/bin" \
		"$bootstrap_home/.linuxbrew/opt/ruby/bin" \
		"$cold_bin" \
		"$cold_home" \
		"$fake_bin" \
		"$repo"
	printf '# Smoke\n' >"$repo/README.md"
	git -C "$repo" init -q
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	git -C "$repo" add README.md
	git -C "$repo" commit -q -m init

	write_bootstrap_state "$bootstrap_home" "$(platform_name)"
	HOME=$bootstrap_home "$preflight" --require README.md "$repo" >/dev/null

	cat >"$cold_bin/xcode-select" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	chmod +x "$cold_bin/xcode-select"
	if HOME=$cold_home PATH=$cold_bin:/usr/bin:/bin "$bootstrap" --check macos >/dev/null 2>"$err"; then
		echo "expected bootstrap check detail to fail" >&2
		exit 1
	fi
	grep -q "xcode-command-line-tools-missing" "$err"

	if HOME=$bootstrap_home "$preflight" --require missing "$repo" >/dev/null 2>"$err"; then
		echo "expected missing required path to fail" >&2
		exit 1
	fi
	grep -q "required checkout path is missing or unreadable" "$err"

	cat >"$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
	cat >"$fake_bin/fileproviderctl" <<'EOF'
#!/usr/bin/env bash
cat <<'STATUS'
isDownloading = 1;
isKeepDownloaded = 0;
isRecursivelyDownloaded = 0;
STATUS
EOF
	chmod +x "$fake_bin/fileproviderctl" "$fake_bin/uname"

	write_bootstrap_state "$bootstrap_home" macos
	HOME=$bootstrap_home PATH=$fake_bin:$PATH "$preflight" "$repo" >/dev/null 2>"$err"
	grep -q "checkout is downloading" "$err"
	grep -q "checkout is not marked keep downloaded" "$err"
	grep -q "checkout is not recursively downloaded" "$err"

	cat >"$bootstrap_bin/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	cat >"$bootstrap_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	cat >"$bootstrap_home/.linuxbrew/bin/brew" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in
--prefix)
	if (($# == 1)); then
		printf '%s\n' "$HOME/.linuxbrew"
	else
		printf '%s/opt/%s\n' "$HOME/.linuxbrew" "$2"
	fi
	;;
install | update)
	;;
shellenv)
	printf 'export PATH="%s/bin:$PATH"\n' "$HOME/.linuxbrew"
	;;
*)
	exit 1
	;;
esac
EOF
	cat >"$bootstrap_home/.linuxbrew/opt/curl/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl fake-homebrew\n'
EOF
	mkdir -p "$bootstrap_home/.linuxbrew/opt/git/bin"
	cat >"$bootstrap_home/.linuxbrew/opt/git/bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git fake-homebrew\n'
EOF
	cat >"$bootstrap_home/.linuxbrew/opt/ruby/bin/ruby" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -ryaml ]]; then
	shift
	exec /usr/bin/ruby -ryaml -rdate "$@"
fi

printf 'ruby fake-homebrew\n'
EOF
	chmod +x \
		"$bootstrap_bin/apt-get" \
		"$bootstrap_bin/sudo" \
		"$bootstrap_home/.linuxbrew/bin/brew" \
		"$bootstrap_home/.linuxbrew/opt/curl/bin/curl" \
		"$bootstrap_home/.linuxbrew/opt/git/bin/git" \
		"$bootstrap_home/.linuxbrew/opt/ruby/bin/ruby"

	HOME=$bootstrap_home PATH=$bootstrap_bin:/usr/bin:/bin "$bootstrap" linux >"$bootstrap_out"
	grep -q "ruby fake-homebrew" "$bootstrap_out"
	grep -q "git fake-homebrew" "$bootstrap_out"
	grep -q "curl fake-homebrew" "$bootstrap_out"
	grep -Fq "$bootstrap_home/.linuxbrew/bin/brew shellenv" "$bootstrap_home/.profile"
	grep -q "bootstrap:" "$bootstrap_home/.local/state/tilde/hosts/$(host_name)/state.md"
	HOME=$bootstrap_home PATH=$bootstrap_bin:/usr/bin:/bin "$bootstrap" --check linux >"$bootstrap_out"
	grep -q "OK: bootstrap state" "$bootstrap_out"
	rm -f "$bootstrap_home/.local/state/tilde/hosts/$(host_name)/state.md"
	HOME=$bootstrap_home PATH=$bootstrap_bin:/usr/bin:/bin "$preflight" --require README.md "$repo" >/dev/null
	grep -q "bootstrap:" "$bootstrap_home/.local/state/tilde/hosts/$(host_name)/state.md"
	cat >"$bootstrap_home/.local/state/tilde/hosts/$(host_name)/state.md" <<'EOF'
---
[
---
EOF
	HOME=$bootstrap_home PATH=$bootstrap_bin:/usr/bin:/bin "$preflight" --require README.md "$repo" >/dev/null
	grep -q "bootstrap:" "$bootstrap_home/.local/state/tilde/hosts/$(host_name)/state.md"

	mkdir -p \
		"$auto_home/.linuxbrew/bin" \
		"$auto_home/.linuxbrew/opt/curl/bin" \
		"$auto_home/.linuxbrew/opt/git/bin" \
		"$auto_home/.linuxbrew/opt/ruby/bin"
	cat >"$auto_home/.linuxbrew/bin/brew" <<'EOF'
#!/usr/bin/env bash
write_tool() {
	local formula=$1
	local name=$2

	mkdir -p "$HOME/.linuxbrew/opt/$formula/bin"
	case $formula in
	ruby)
		cat >"$HOME/.linuxbrew/opt/$formula/bin/$name" <<'TOOL'
#!/usr/bin/env bash
if [[ ${1:-} == -ryaml ]]; then
	shift
	exec /usr/bin/ruby -ryaml -rdate "$@"
fi

printf 'ruby fake-homebrew\n'
TOOL
		;;
	*)
		cat >"$HOME/.linuxbrew/opt/$formula/bin/$name" <<'TOOL'
#!/usr/bin/env bash
printf '%s fake-homebrew\n' "$(basename "$0")"
TOOL
		;;
	esac
	chmod +x "$HOME/.linuxbrew/opt/$formula/bin/$name"
}

case ${1:-} in
--prefix)
	if (($# == 1)); then
		printf '%s\n' "$HOME/.linuxbrew"
	else
		printf '%s/opt/%s\n' "$HOME/.linuxbrew" "$2"
	fi
	;;
install)
	shift
	for formula; do
		case $formula in
		curl | git | ruby)
			write_tool "$formula" "$formula"
			;;
		esac
	done
	;;
update)
	;;
shellenv)
	printf 'export PATH="%s/bin:$PATH"\n' "$HOME/.linuxbrew"
	;;
*)
	exit 1
	;;
esac
EOF
	printf '#!/usr/bin/env bash\nexit 1\n' >"$auto_home/.linuxbrew/opt/curl/bin/curl"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$auto_home/.linuxbrew/opt/git/bin/git"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$auto_home/.linuxbrew/opt/ruby/bin/ruby"
	chmod +x \
		"$auto_home/.linuxbrew/bin/brew" \
		"$auto_home/.linuxbrew/opt/curl/bin/curl" \
		"$auto_home/.linuxbrew/opt/git/bin/git" \
		"$auto_home/.linuxbrew/opt/ruby/bin/ruby"
	HOME=$auto_home PATH=$bootstrap_bin:/usr/bin:/bin "$preflight" --require README.md "$repo" >/dev/null 2>"$err"
	grep -q "bootstrap check failed; running bootstrap" "$err"
	grep -q "bootstrap:" "$auto_home/.local/state/tilde/hosts/$(host_name)/state.md"

	tree=$(git -C "$repo" rev-parse 'HEAD^{tree}')
	object=$repo/.git/objects/${tree:0:2}/${tree:2}
	rm -f "$object"

	write_bootstrap_state "$bootstrap_home" "$(platform_name)"
	if HOME=$bootstrap_home "$preflight" "$repo" >/dev/null 2>"$err"; then
		echo "expected missing Git tree object to fail" >&2
		exit 1
	fi
	grep -q "checkout has no readable Git HEAD tree" "$err"
}

main "$@"
