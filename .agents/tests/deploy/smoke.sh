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

write_git_repo() {
	local repo=$1
	local name=${2:-repo}

	mkdir -p "$repo"
	git -C "$repo" init -q
	git -C "$repo" checkout -q -B main
	git -C "$repo" config user.email smoke@example.invalid
	git -C "$repo" config user.name Smoke
	printf '# %s\n' "$name" >"$repo/README.md"
	git -C "$repo" add README.md
	git -C "$repo" commit -q -m init
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local home
	local out
	local repo
	local remote_home
	local ssh_args
	local ssh_script
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
	remote_home=$tmpdir/remote-home
	ssh_args=$tmpdir/ssh.args
	ssh_script=$tmpdir/ssh
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
		abort "expected missing required path to fail"
	fi
	grep -Fq "required checkout path is missing" "$out"

	mkdir -p "$remote_home/.agents/skills" "$remote_home/Dropbox"
	write_fake_bootstrap "$remote_home"
	write_git_repo "$remote_home/Dropbox/home" home
	write_git_repo "$remote_home/Dropbox/home-" home-
	git clone -q "$skill_root" "$remote_home/Dropbox/tilde"
	git -C "$remote_home/Dropbox/tilde" checkout -q "$(git -C "$skill_root" rev-parse HEAD)"
	git clone -q "$skill_root" "$remote_home/.agents/skills/tilde"
	git -C "$remote_home/.agents/skills/tilde" checkout -q "$(git -C "$skill_root" rev-parse HEAD)"
	mkdir -p "$remote_home/.local/state/tilde"
	cat >"$remote_home/.local/state/tilde/state.yml" <<EOF
public: "~/Dropbox/home"
private: "~/Dropbox/home-"
applied:
  public: $(git -C "$remote_home/Dropbox/home" rev-parse HEAD)
  private: $(git -C "$remote_home/Dropbox/home-" rev-parse HEAD)
EOF

cat >"$ssh_script" <<'EOF'
#!/usr/bin/env bash
set -e
printf '%s\n' "$@" >"$TILDE_FAKE_SSH_ARGS"
shift
interpreter=$1
shift
export HOME=$TILDE_FAKE_REMOTE_HOME
export PATH=/usr/bin:/bin
exec "$interpreter" "$@"
EOF
	chmod +x "$ssh_script"
	PATH=$tmpdir:$PATH TILDE_FAKE_REMOTE_HOME=$remote_home TILDE_FAKE_SSH_ARGS=$ssh_args \
		"$tilde" preflight remote spinoza --format json >"$out"
	ruby -rjson -e '
	  data = JSON.parse(File.read(ARGV[0]))
	  abort "backend" unless data["backend"] == "dropbox"
	  abort "bootstrap" unless data.dig("bootstrap", "needed") == false
	  abort "public repo" unless data.dig("repositories", "public", "exists") == true
	  abort "private repo" unless data.dig("repositories", "private", "exists") == true
	  abort "runtime" unless data.dig("runtime", "current") == true
	  abort "dropbox runtime" unless data.dig("dropbox_runtime", "current") == true
	  abort "link step" unless data["next"].include?("link-dropbox-runtime")
	  abort "dropbox repo step" unless data["next"].include?("use-target-dropbox-repositories")
	' "$out"

	printf 'scratch\n' >"$remote_home/.agents/skills/tilde/scratch.txt"
	PATH=$tmpdir:$PATH TILDE_FAKE_REMOTE_HOME=$remote_home TILDE_FAKE_SSH_ARGS=$ssh_args \
		"$tilde" preflight remote spinoza --format json >"$out"
	ruby -rjson -e '
	  data = JSON.parse(File.read(ARGV[0]))
	  abort "runtime should be dirty" unless data.dig("runtime", "dirty") == true
	  abort "dirty runtime should block runtime link" if data["next"].include?("link-dropbox-runtime")
	  abort "missing clean runtime step" unless data["next"].include?("clean-target-runtime")
	' "$out"
	rm -f "$remote_home/.agents/skills/tilde/scratch.txt"

	echo "deploy smoke ok"
}

main "$@"
