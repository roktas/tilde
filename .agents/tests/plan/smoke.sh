#!/usr/bin/env bash

set -Eeuo pipefail
[[ -z ${TRACE:-} ]] || set -x
unset CDPATH

cleanup_extra_module=
cleanup_platform_module=
cleanup_refresh_module=
cleanup_repair_repo=
cleanup_target_module=
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
	rm -rf "$cleanup_extra_module" "$cleanup_platform_module" "$cleanup_refresh_module" "$cleanup_target_module"
	[[ -z $cleanup_repair_repo ]] || rm -rf "$cleanup_repair_repo"
	[[ -z $cleanup_tmpdir ]] || rm -rf "$cleanup_tmpdir"
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local align_plan_json
	local align_state_plan_json
	local dirty_plan_err
	local dirty_repo
	local extra_module
	local extra_plan_json
	local file_provider_plan_json
	local file_provider_repo
	local full_refresh_plan_json
	local head
	local invalid_plan_err
	local invalid_plan_json
	local macos_plan_json
	local normal_plan_json
	local platform_module
	local plan_impl
	local plan_json
	local private_extra_plan_json
	local private_macos_extra_plan_json
	local private_macos_plan_json
	local private_plan_json
	local private_repo
	local refresh_plan_json
	local refresh_module
	local repair_repo=
	local repair_plan_json
	local repo
	local script_dir
	local skill_root
	local state_skip_plan_json
	local stored_level_plan_json
	local target_module
	local target_plan_json
	local tilde
	local tmpdir
	local upgrade_plan_json

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	tilde=$skill_root/bin/tilde
	plan_impl=$skill_root/libexec/plan
	repo=${REPO_ROOT:-$(cd -- "$skill_root/../home" >/dev/null && pwd)}
	private_repo=${PRIVATE_REPO_ROOT:-}
	if [[ -z $private_repo && -d $repo/../home- ]]; then
		private_repo=$(cd -- "$repo/../home-" >/dev/null && pwd)
	fi
	extra_module=$repo/zz-extra-smoke
	platform_module=$repo/zz-platform-smoke
	refresh_module=$repo/zz-refresh-smoke
	target_module=$repo/zz-target-smoke
	cleanup_extra_module=$extra_module
	cleanup_platform_module=$platform_module
	cleanup_refresh_module=$refresh_module
	cleanup_target_module=$target_module

	trap cleanup EXIT HUP INT QUIT TERM

	cd "$repo"

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	export XDG_STATE_HOME=$tmpdir/state
	align_plan_json=$tmpdir/align-plan.json
	align_state_plan_json=$tmpdir/align-state-plan.json
	dirty_plan_err=$tmpdir/dirty-plan.err
	extra_plan_json=$tmpdir/extra-plan.json
	file_provider_plan_json=$tmpdir/file-provider-plan.json
	full_refresh_plan_json=$tmpdir/full-refresh-plan.json
	invalid_plan_err=$tmpdir/invalid-package-plan.err
	invalid_plan_json=$tmpdir/invalid-package-plan.json
	macos_plan_json=$tmpdir/macos-plan.json
	normal_plan_json=$tmpdir/normal-plan.json
	plan_json=$tmpdir/plan.json
	private_extra_plan_json=$tmpdir/private-extra-plan.json
	private_macos_extra_plan_json=$tmpdir/private-macos-extra-plan.json
	private_macos_plan_json=$tmpdir/private-macos-plan.json
	private_plan_json=$tmpdir/private-plan.json
	refresh_plan_json=$tmpdir/refresh-plan.json
	repair_plan_json=$tmpdir/repair-plan.json
	state_skip_plan_json=$tmpdir/state-skip-plan.json
	stored_level_plan_json=$tmpdir/stored-level-plan.json
	target_plan_json=$tmpdir/target-plan.json
	upgrade_plan_json=$tmpdir/upgrade-plan.json

	export GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL:-$tmpdir/gitconfig}

	git config --global --add safe.directory "$repo"
	[[ -z $private_repo ]] || git config --global --add safe.directory "$private_repo"

	ruby -c "$plan_impl"

	dirty_repo=$tmpdir/dirty-repo
	mkdir -p "$dirty_repo"
	cat >"$dirty_repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
---

# Dirty Guard
EOF
	git -C "$dirty_repo" init -q
	git -C "$dirty_repo" config user.email smoke@example.invalid
	git -C "$dirty_repo" config user.name Smoke
	git -C "$dirty_repo" add .
	git -C "$dirty_repo" commit -q -m init
	printf '\n' >>"$dirty_repo/AGENTS.md"

	if "$tilde" plan --repo "$dirty_repo" >"$plan_json" 2>"$dirty_plan_err"; then
		abort "expected dirty worktree guard to fail"
	fi

	grep -q "Dirty worktree" "$dirty_plan_err"

	"$tilde" plan --repo "$repo" --allow-dirty --platform linux --host smoke >"$plan_json"

	PLAN_JSON=$plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("PLAN_JSON")))
		abort "wrong schema" unless plan.fetch("schema") == "tilde.plan/v1"
		abort "missing plan id" unless plan.fetch("plan_id").start_with?("sha256:")
		abort "wrong repository role" unless plan.fetch("repository").fetch("role") == "public"
		abort "wrong target host" unless plan.fetch("target").fetch("host") == "smoke"
		abort "wrong target platform" unless plan.fetch("target").fetch("platform") == "linux"
		actions = plan.fetch("actions")
		abort "missing actions stream" if actions.empty?
		ids = actions.map { |action| action.fetch("id") }
		abort "action ids should be unique" unless ids.uniq == ids
		abort "actions should use role-qualified module ids" unless actions.all? { |action| action.fetch("module_id") == "core" || action.fetch("module_id").include?("/") }
		abort "home-entrypoint action kind leaked" if actions.any? { |action| action.fetch("kind") == "home-entrypoint" }
		abort "missing linux install section action" unless actions.any? { |action| action.fetch("kind") == "section" && action.fetch("module_id") == "public/linux" && action.fetch("name") == "Install" && action.fetch("bash_only") == true }
		abort "missing agents link action" unless actions.any? { |action| action.fetch("kind") == "link" && action.fetch("module_id") == "public/agents" && action.fetch("target") == "~/.agents/AGENTS.md" && action.fetch("link_value").end_with?("/agents/AGENTS.md") }
		abort "wrong mode" unless plan.fetch("mode") == "apply"
		abort "wrong level" unless plan.fetch("level") == "normal"
		abort "wrong platform" unless plan.fetch("platform") == "linux"
		core_entrypoints = plan.fetch("core").fetch("home_entrypoints_to_write")
		home_entrypoint_linked = plan.fetch("modules").any? { |mod| mod.fetch("links_to_create").any? { |link| link.fetch("target") == "~/AGENTS.md" } }
		abort "core should not create home entrypoint symlink actions" unless plan.fetch("core").fetch("links_to_create").empty?
		if home_entrypoint_linked
			abort "module-owned home entrypoint should suppress fallback" unless core_entrypoints.empty?
		elsif core_entrypoints.empty?
			# Companion-owned home entrypoints are checked by a focused fixture below.
		else
			abort "missing fallback home entrypoint" unless core_entrypoints.any? { |entrypoint| entrypoint.fetch("source") == "assets/AGENTS.md" && entrypoint.fetch("target") == "~/AGENTS.md" && entrypoint.fetch("strategy") == "write-fallback-file" }
			abort "missing fallback entrypoint action" unless actions.any? { |action| action.fetch("kind") == "entrypoint" && action.fetch("module_id") == "core" && action.fetch("target") == "~/AGENTS.md" }
		end
		linux = plan.fetch("modules").find { |mod| mod.fetch("name") == "linux" }
		abort "missing linux platform module" unless linux
		abort "wrong linux module id" unless linux.fetch("id") == "public/linux"
		abort "linux platform module should be first" unless plan.fetch("modules").first.fetch("name") == "linux"
		abort "missing linux install section" unless linux.fetch("special_sections").key?("Install")
		abort "linux platform module should install shared shell tools" unless linux.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:zoxide" }
		misc = plan.fetch("modules").find { |mod| mod.fetch("name") == "misc" }
		abort "missing misc module" unless misc
		abort "misc module should run alphabetically" unless plan.fetch("modules").map { |mod| mod.fetch("name") }.index("misc") > plan.fetch("modules").map { |mod| mod.fetch("name") }.index("markdown")
		chrome = plan.fetch("modules").find { |mod| mod.fetch("name") == "chrome" }
		abort "missing chrome module" unless chrome
		abort "missing chrome linux install section" unless chrome.fetch("special_sections").dig("Install", "body").include?("google-chrome-beta")
		abort "chrome linux plan should not install macos cask" unless chrome.fetch("packages_to_install").empty?
		abort "linux dash variant should not be planned at normal level" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "linux-" }
		agents = plan.fetch("modules").find { |mod| mod.fetch("name") == "agents" }
		abort "missing agents module" unless agents
		abort "agents should default to normal level" unless agents.fetch("level") == "normal"
		abort "agents should be a virtual shared-asset module" unless agents.fetch("virtual") == true
		abort "agents should not install agent-specific packages" unless agents.fetch("packages_to_install").empty?
		abort "agents should not own the home entrypoint" if agents.fetch("links_to_create").any? { |link| link.fetch("target") == "~/AGENTS.md" }
		abort "agents should link shared instructions under ~/.agents" unless agents.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.agents/AGENTS.md" }
		abort "agents should keep common skills under ~/.agents" unless agents.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.agents/skills/colon" }
		abort "agents should expose common commits skill under ~/.agents" unless agents.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.agents/skills/commits" }
		abort "agents should not expose the tilde control plane" if agents.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.agents/skills/tilde" }
		abort "agents should not expose system skills globally" if agents.fetch("links_to_create").any? { |link| link.fetch("target").include?("/.system") }
		abort "agents colon skill should be the common source" if File.symlink?("agents/skills/colon")
		abort "agents TILDE alias should be removed" if File.exist?("agents/TILDE.md")
		abort "agents- module should be removed" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "agents-" }
		abort "codex should be a private module" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "codex" }
		abort "opencode should be a private module" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "opencode" }
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module" unless git
		abort "git should not be virtual" unless git.fetch("virtual") == false
		abort "missing brew:git" unless git.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:git" }
		abort "missing git config link" unless git.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.config/git/config" }
		abort "missing git bin fan-in link" unless git.fetch("links_to_create").any? { |link| link.fetch("source") == "bin/git-renew" && link.fetch("target") == "~/.local/bin/git-renew" && link.fetch("fan_in") == true }
		mc = plan.fetch("modules").find { |mod| mod.fetch("name") == "mc" }
		abort "missing mc module" unless mc
		abort "missing mc.ini seed" unless mc.fetch("seeds_to_create").any? { |seed| seed.fetch("target") == "~/.config/mc/ini" }
		abort "missing mc skins copy" unless mc.fetch("copies_to_create").any? { |copy| copy.fetch("target") == "~/.local/share/mc/skins" }
		abort "gnome module should not be planned" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "gnome" }
	'

	head=$(git -C "$repo" rev-parse HEAD)
	mkdir -p "$XDG_STATE_HOME/tilde"
	cat >"$XDG_STATE_HOME/tilde/state.yml" <<EOF
protocol: tilde/v1
public: $repo
applied:
  level: normal
  platform: linux
  public: $head
EOF

	"$tilde" plan --repo "$repo" --allow-dirty --platform linux --host smoke >"$state_skip_plan_json"
	"$tilde" plan --repo "$repo" --allow-dirty --mode align --platform linux --host smoke >"$align_state_plan_json"

	STATE_SKIP_PLAN_JSON=$state_skip_plan_json ALIGN_STATE_PLAN_JSON=$align_state_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("STATE_SKIP_PLAN_JSON")))
		linux = plan.fetch("modules").find { |mod| mod.fetch("name") == "linux" }
		abort "missing linux module" unless linux
		abort "state must not skip linux module" if linux.fetch("skipped")
		abort "linux packages should still be planned" if linux.fetch("packages_to_install").empty?
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module" unless git
		abort "state must not skip git module" if git.fetch("skipped")
		abort "git packages should still be planned" if git.fetch("packages_to_install").empty?
		abort "git links should still be planned" if git.fetch("links_to_create").empty?
		mc = plan.fetch("modules").find { |mod| mod.fetch("name") == "mc" }
		abort "missing mc module" unless mc
		abort "state must not skip mc module" if mc.fetch("skipped")
		align = JSON.parse(File.read(ENV.fetch("ALIGN_STATE_PLAN_JSON")))
		align_git = align.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing align git module" unless align_git
		abort "align should not skip from state" if align_git.fetch("skipped")
		abort "align should keep git links" if align_git.fetch("links_to_create").empty?
	'

	cat >"$XDG_STATE_HOME/tilde/state.yml" <<EOF
protocol: tilde/v1
public: $repo
applied:
  level: minimal
  platform: linux
  public: $head
EOF
	"$tilde" plan --repo "$repo" --allow-dirty --platform linux --host smoke >"$stored_level_plan_json"
	STORED_LEVEL_PLAN_JSON=$stored_level_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("STORED_LEVEL_PLAN_JSON")))
		abort "plan should reuse stored level" unless plan.fetch("level") == "minimal"
		abort "target should reuse stored level" unless plan.fetch("target").fetch("level") == "minimal"
		abort "stored minimal level should exclude normal modules" if plan.fetch("modules").any? { |mod| mod.fetch("level") == "normal" }
	'
	rm -f "$XDG_STATE_HOME/tilde/state.yml"

	if [[ -n $private_repo ]]; then
		"$tilde" plan --repo "$private_repo" --allow-dirty --platform linux --host newton >"$private_plan_json"
		"$tilde" plan --repo "$private_repo" --allow-dirty --level extra --platform linux --host newton >"$private_extra_plan_json"
		"$tilde" plan --repo "$private_repo" --allow-dirty --platform macos --host kant >"$private_macos_plan_json"
		"$tilde" plan --repo "$private_repo" --allow-dirty --level extra --platform macos --host kant >"$private_macos_extra_plan_json"

		PRIVATE_PLAN_JSON=$private_plan_json PRIVATE_EXTRA_PLAN_JSON=$private_extra_plan_json PRIVATE_MACOS_PLAN_JSON=$private_macos_plan_json PRIVATE_MACOS_EXTRA_PLAN_JSON=$private_macos_extra_plan_json ruby -rjson -e '
			linux = JSON.parse(File.read(ENV.fetch("PRIVATE_PLAN_JSON")))
			baseline = linux.fetch("modules").find { |mod| mod.fetch("name") == "linux" }
			abort "missing private linux baseline" unless baseline
			abort "private linux baseline should be early" unless baseline.fetch("phase") == "early"
			abort "private linux baseline should emit early actions" unless linux.fetch("actions").any? { |action| action.fetch("module_id") == "private/linux" && action.fetch("phase") == "early" }
			abort "linux codex should be extra-only" if linux.fetch("modules").any? { |mod| mod.fetch("name") == "codex" }
			linux_extra = JSON.parse(File.read(ENV.fetch("PRIVATE_EXTRA_PLAN_JSON")))
			codex = linux_extra.fetch("modules").find { |mod| mod.fetch("name") == "codex" }
			abort "missing private codex module" unless codex
			abort "missing linux codex-switcher package" unless codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "github:Lampese/codex-switcher" }
			abort "linux codex should not install codex cask" if codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:codex" }
			abort "codex wrappers should be removed" if codex.fetch("links_to_create").any? { |link| link.fetch("source") == "bin/codex" || link.fetch("target") == "~/Dropbox/_/bin/codex" || link.fetch("source") == "bin/codex-switcher" || link.fetch("target") == "~/Dropbox/_/bin/codex-switcher" }
			abort "codex should link hooks into shared codex state" unless codex.fetch("links_to_create").any? { |link| link.fetch("source") == "hooks/shellcheck" && link.fetch("target") == "~/Dropbox/_/var/codex/hooks/shellcheck" && link.fetch("fan_in") == true }
			hook_action = linux_extra.fetch("actions").find { |action| action.fetch("kind") == "link" && action.fetch("target") == "~/Dropbox/_/var/codex/hooks/shellcheck" }
			abort "missing codex hook action" unless hook_action
			abort "codex hook should use a relative Dropbox link value" unless hook_action.fetch("link_value") == "../../../../home-/codex/hooks/shellcheck"
			abort "codex should expose shared agent instructions" unless codex.fetch("links_to_create").any? { |link| link.fetch("source") == "~/Dropbox/home/agents/AGENTS.md" && link.fetch("target") == "~/Dropbox/_/var/codex/AGENTS.md" && link.fetch("source_external") == true }
			abort "codex should keep auth host-local" if codex.fetch("links_to_create").any? { |link| link.fetch("source") == "~/Dropbox/_/var/codex/auth.json" || link.fetch("target") == "~/.codex/auth.json" }
			copilot = linux.fetch("modules").find { |mod| mod.fetch("name") == "copilot" }
			abort "missing linux copilot module" unless copilot
			abort "missing linux copilot-cli cask" unless copilot.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:copilot-cli" }
			abort "linux copilot wrapper should be removed" if copilot.fetch("links_to_create").any? { |link| link.fetch("source") == "bin/copilot" || link.fetch("target") == "~/Dropbox/_/bin/copilot" }
			abort "copilot should export COPILOT_HOME through environment.d" unless copilot.fetch("links_to_create").any? { |link| link.fetch("source") == "environment.d/copilot.conf" && link.fetch("target") == "~/.config/environment.d/copilot.conf" }
			abort "copilot should create shared state directory" unless copilot.fetch("directories_to_create").any? { |dir| dir.fetch("target") == "~/Dropbox/_/var/copilot" }
			abort "copilot should expose shared instructions" unless copilot.fetch("links_to_create").any? { |link| link.fetch("source") == "~/Dropbox/home/agents/AGENTS.md" && link.fetch("target") == "~/Dropbox/_/var/copilot/copilot-instructions.md" && link.fetch("source_external") == true }
			environment = linux.fetch("modules").find { |mod| mod.fetch("name") == "environment" }
			abort "missing linux environment module" unless environment
			abort "environment should link linux session.conf" unless environment.fetch("links_to_create").any? { |link| link.fetch("source") == "environment.d/session.linux.conf" && link.fetch("target") == "~/.config/environment.d/session.conf" }
			abort "environment should not link variables file" if environment.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.config/environment/variables" || link.fetch("target") == "~/.config/environment.d/00-base.conf" }
			abort "dropignore module should be removed" if linux.fetch("modules").any? { |mod| mod.fetch("name") == "dropignore" }
			opencode = linux.fetch("modules").find { |mod| mod.fetch("name") == "opencode" }
			abort "missing private opencode module" unless opencode
			abort "missing opencode package" unless opencode.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:opencode" }
			abort "opencode should not install aicommits package" if opencode.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:aicommits" }
			abort "opencode should create shared config directory" unless opencode.fetch("directories_to_create").any? { |dir| dir.fetch("target") == "~/Dropbox/_/var/opencode/config" }
			abort "opencode should create shared data directory" unless opencode.fetch("directories_to_create").any? { |dir| dir.fetch("target") == "~/Dropbox/_/var/opencode/share" }
			abort "opencode should link XDG config to shared state" unless opencode.fetch("links_to_create").any? { |link| link.fetch("source") == "~/Dropbox/_/var/opencode/config" && link.fetch("target") == "~/.config/opencode" && link.fetch("source_external") == true }
			abort "opencode should link XDG data to shared state" unless opencode.fetch("links_to_create").any? { |link| link.fetch("source") == "~/Dropbox/_/var/opencode/share" && link.fetch("target") == "~/.local/share/opencode" && link.fetch("source_external") == true }
			abort "opencode should use shared agent instructions" unless opencode.fetch("links_to_create").any? { |link| link.fetch("source") == "~/Dropbox/home/agents/AGENTS.md" && link.fetch("target") == "~/Dropbox/_/var/opencode/config/AGENTS.md" && link.fetch("source_external") == true }
			abort "opencode should not link skills directly" if opencode.fetch("links_to_create").any? { |link| link.fetch("target").include?("/skills/") }

			macos = JSON.parse(File.read(ENV.fetch("PRIVATE_MACOS_PLAN_JSON")))
			abort "macos codex should be extra-only" if macos.fetch("modules").any? { |mod| mod.fetch("name") == "codex" }
			macos_extra = JSON.parse(File.read(ENV.fetch("PRIVATE_MACOS_EXTRA_PLAN_JSON")))
			macos_codex = macos_extra.fetch("modules").find { |mod| mod.fetch("name") == "codex" }
			abort "missing macos codex module" unless macos_codex
			abort "missing macos codex cask" unless macos_codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:codex" }
			abort "macos codex should not install codex-switcher release" if macos_codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "github:Lampese/codex-switcher" }
			macos_environment = macos.fetch("modules").find { |mod| mod.fetch("name") == "environment" }
			abort "missing macos environment module" unless macos_environment
			abort "environment should link macos session.conf" unless macos_environment.fetch("links_to_create").any? { |link| link.fetch("source") == "environment.d/session.macos.conf" && link.fetch("target") == "~/.config/environment.d/session.conf" }
			abort "macos environment should not link variables file" if macos_environment.fetch("links_to_create").any? { |link| link.fetch("target") == "~/.config/environment/variables" || link.fetch("target") == "~/.config/environment.d/00-base.conf" }
			copilot = macos.fetch("modules").find { |mod| mod.fetch("name") == "copilot" }
			abort "missing macos copilot module" unless copilot
			abort "missing macos copilot-cli cask" unless copilot.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:copilot-cli" }
			abort "copilot wrapper should be removed" if copilot.fetch("links_to_create").any? { |link| link.fetch("source") == "bin/copilot" || link.fetch("target") == "~/Dropbox/_/bin/copilot" }
			abort "macos dropignore module should be removed" if macos.fetch("modules").any? { |mod| mod.fetch("name") == "dropignore" }
		'
	fi

	file_provider_repo=$tmpdir/file-provider/Library/CloudStorage/Dropbox/home-
	mkdir -p "$file_provider_repo/codex/bin" "$file_provider_repo/codex/hooks"
	cat >"$file_provider_repo/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: private
---

# Private File Provider Smoke
EOF
	cat >"$file_provider_repo/codex/README.md" <<'EOF'
---
all:
  links:
    bin/codex-switcher: ~/Dropbox/_/bin/codex-switcher
    hooks/: ~/Dropbox/_/var/codex/hooks
---

# Codex
EOF
	touch "$file_provider_repo/codex/bin/codex-switcher" "$file_provider_repo/codex/hooks/shellcheck"

	git -C "$file_provider_repo" init -q
	git -C "$file_provider_repo" config user.email smoke@example.invalid
	git -C "$file_provider_repo" config user.name Smoke
	git -C "$file_provider_repo" add AGENTS.md codex
	git -C "$file_provider_repo" commit -q -m init

	HOME=$tmpdir/file-provider "$tilde" plan --repo "$file_provider_repo" --platform macos --host smoke >"$file_provider_plan_json"

	FILE_PROVIDER_PLAN_JSON=$file_provider_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("FILE_PROVIDER_PLAN_JSON")))
		dropbox_actions = plan.fetch("actions").select { |action| action.fetch("kind") == "link" && action.fetch("target").start_with?("~/Dropbox/") }
		abort "missing Dropbox actions" if dropbox_actions.empty?
		absolute = dropbox_actions.find { |action| action.fetch("link_value").start_with?("/") }
		abort "Dropbox action should not use host-absolute link value: #{absolute.fetch("id")}" if absolute
		wrapper = dropbox_actions.find { |action| action.fetch("target") == "~/Dropbox/_/bin/codex-switcher" }
		abort "missing file-provider wrapper link" unless wrapper
		abort "wrapper should use logical Dropbox-relative value" unless wrapper.fetch("link_value") == "../../home-/codex/bin/codex-switcher"
		hook = dropbox_actions.find { |action| action.fetch("target") == "~/Dropbox/_/var/codex/hooks/shellcheck" }
		abort "missing file-provider hook link" unless hook
		abort "hook should use logical Dropbox-relative value" unless hook.fetch("link_value") == "../../../../home-/codex/hooks/shellcheck"
	'

	rm -rf "$target_module"
	mkdir -p "$target_module/bin"
	touch "$target_module/AGENTS.md" "$target_module/config" "$target_module/bin/tool"
	cat >"$target_module/README.md" <<'EOF'
---
all:
  links:
    AGENTS.md: ~/AGENTS.md
    config:
      - ~/.config/target-list/a
      - ~/.config/target-list/b
    bin/:
      - ~/.local/bin
      - ~/.local/sbin
---

# Target List Smoke
EOF

	"$tilde" plan --repo "$repo" --allow-dirty --platform linux --host smoke >"$target_plan_json"

	TARGET_PLAN_JSON=$target_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("TARGET_PLAN_JSON")))
		smoke = plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-target-smoke" }
		abort "missing target module" unless smoke
		abort "home entrypoint module link should suppress fallback" unless plan.fetch("core").fetch("home_entrypoints_to_write").empty?
		links = smoke.fetch("links_to_create")
		abort "missing home entrypoint link" unless links.any? { |link| link.fetch("source") == "AGENTS.md" && link.fetch("target") == "~/AGENTS.md" }
		abort "missing first scalar source target" unless links.any? { |link| link.fetch("source") == "config" && link.fetch("target") == "~/.config/target-list/a" }
		abort "missing second scalar source target" unless links.any? { |link| link.fetch("source") == "config" && link.fetch("target") == "~/.config/target-list/b" }
		abort "missing first fan-in list target" unless links.any? { |link| link.fetch("source") == "bin/tool" && link.fetch("target") == "~/.local/bin/tool" && link.fetch("fan_in") == true }
		abort "missing second fan-in list target" unless links.any? { |link| link.fetch("source") == "bin/tool" && link.fetch("target") == "~/.local/sbin/tool" && link.fetch("fan_in") == true }
	'

	local companion_plan_json=$tmpdir/companion-plan.json
	local companion_private=$tmpdir/private
	local companion_public=$tmpdir/public

	mkdir -p "$companion_private/home" "$companion_public"
	cat >"$companion_public/AGENTS.md" <<'EOF'
---
tilde:
  protocol: tilde/v1
  role: public
  private: ../private
---

# Public Smoke
EOF
	cat >"$companion_private/home/README.md" <<'EOF'
---
all:
  links:
    AGENTS.md: ~/AGENTS.md
---

# Home
EOF
	touch "$companion_private/home/AGENTS.md"

	git -C "$companion_public" init -q
	git -C "$companion_public" config user.email smoke@example.invalid
	git -C "$companion_public" config user.name Smoke
	git -C "$companion_public" add AGENTS.md
	git -C "$companion_public" commit -q -m init

	"$tilde" plan --repo "$companion_public" --platform linux --host smoke >"$companion_plan_json"

	COMPANION_PLAN_JSON=$companion_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("COMPANION_PLAN_JSON")))
		abort "companion-owned home entrypoint should suppress fallback" unless plan.fetch("core").fetch("home_entrypoints_to_write").empty?
	'

	rm -rf "$extra_module"
	mkdir -p "$extra_module"
	cat >"$extra_module/README.md" <<'EOF'
---
level: extra
all:
  packages:
    - brew:extra-smoke
---

# Extra Smoke
EOF

	"$tilde" plan --repo "$repo" --allow-dirty --platform linux --host smoke >"$normal_plan_json"
	"$tilde" plan --repo "$repo" --allow-dirty --level extra --platform linux --host smoke >"$extra_plan_json"

	NORMAL_PLAN_JSON=$normal_plan_json EXTRA_PLAN_JSON=$extra_plan_json ruby -rjson -e '
		normal_plan = JSON.parse(File.read(ENV.fetch("NORMAL_PLAN_JSON")))
		extra_plan = JSON.parse(File.read(ENV.fetch("EXTRA_PLAN_JSON")))
		abort "extra module should not be planned at normal level" if normal_plan.fetch("modules").any? { |mod| mod.fetch("name") == "zz-extra-smoke" }
		linux_dash = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "linux-" }
		abort "missing linux dash variant at extra level" unless linux_dash
		abort "linux dash variant should follow linux" unless extra_plan.fetch("modules")[1].fetch("name") == "linux-"
		calibre = linux_dash.fetch("packages_to_install").find { |pkg| pkg.fetch("value") == "flatpak:com.calibre_ebook.calibre" }
		abort "missing calibre flatpak package" unless calibre
		abort "calibre should be graphical" unless calibre.fetch("condition") == "graphical"
		calibre_action = extra_plan.fetch("actions").find { |action| action.fetch("id") == "public/linux-:package:install:flatpak:com.calibre_ebook.calibre" }
		abort "missing calibre package action" unless calibre_action
		abort "calibre action should be graphical" unless calibre_action.fetch("condition") == "graphical"
		extra = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-extra-smoke" }
		abort "missing extra module at extra level" unless extra
		abort "wrong extra module level" unless extra.fetch("level") == "extra"
		abort "missing top-level extra module package" unless extra.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:extra-smoke" }
		c = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "c" }
		abort "missing c extra module" unless c
		abort "missing c llvm package" unless c.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:llvm" }
		javascript = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "javascript" }
		abort "missing javascript module" unless javascript
		abort "missing bun formula" unless javascript.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:bun" }
		virtualbox = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "virtualbox" }
		abort "missing virtualbox extra module" unless virtualbox
		abort "virtualbox should be virtual" unless virtualbox.fetch("virtual") == true
		abort "missing virtualbox install section" unless virtualbox.fetch("special_sections").key?("Install")
		abort "missing virtualbox configure section" unless virtualbox.fetch("special_sections").key?("Configure")
		abort "virtualbox should not rely on postinstall" if virtualbox.fetch("special_sections").key?("Post Install")
		ghostty = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "ghostty" }
		abort "missing ghostty module" unless ghostty
		abort "ghostty linux plan should not install cask" if ghostty.fetch("packages_to_install").any? { |pkg| pkg.fetch("type") == "cask" }
		vscode = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "vscode" }
		abort "missing vscode module" unless vscode
		abort "vscode linux plan should not install cask" if vscode.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:visual-studio-code" }
	'

	rm -rf "$platform_module"
	mkdir -p "$platform_module"
	cat >"$platform_module/README.md" <<'EOF'
---
macos: ~
---

# Platform Smoke

## All Platforms

### Install

Run the all-platform setup block.

```bash
echo all
```

## MacOS

### Install

Run the macOS setup block.

```bash
echo macos
```
EOF

	"$tilde" plan --repo "$repo" --allow-dirty --platform macos --host smoke >"$macos_plan_json"

	MACOS_PLAN_JSON=$macos_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("MACOS_PLAN_JSON")))
		abort "gnome should not be planned on macos" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "gnome" }
		abort "linux should not be planned on macos" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "linux" }
		ghostty = plan.fetch("modules").find { |mod| mod.fetch("name") == "ghostty" }
		abort "missing ghostty module on macos" unless ghostty
		abort "missing ghostty macos cask" unless ghostty.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:ghostty" }
		chrome = plan.fetch("modules").find { |mod| mod.fetch("name") == "chrome" }
		abort "missing chrome module on macos" unless chrome
		abort "missing chrome beta macos cask" unless chrome.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:google-chrome@beta" }
		abort "chrome macos plan should not include linux install" if chrome.fetch("special_sections").key?("Install")
		abort "virtualbox should not be planned on macos" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "virtualbox" }
		smoke = plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-platform-smoke" }
		abort "missing platform module" unless smoke
		abort "missing platform install section" unless smoke.fetch("special_sections").key?("Install")
		abort "platform install prose should still be executable" unless smoke.fetch("special_sections").fetch("Install").fetch("bash_only")
		body = smoke.fetch("special_sections").fetch("Install").fetch("body")
		abort "platform scoped sections should preserve document order" unless body.index("echo all") < body.index("echo macos")
	'

	rm -rf "$platform_module"
	mkdir -p "$platform_module"
	cat >"$platform_module/README.md" <<'EOF'
---
all:
  packages:
    - "brew:"
---

# Invalid Package Smoke
EOF

	if "$tilde" plan --repo "$repo" --allow-dirty --platform linux --host smoke >"$invalid_plan_json" 2>"$invalid_plan_err"; then
		abort "expected invalid package name guard to fail"
	fi

	grep -q "Package name must not be empty" "$invalid_plan_err"

	rm -rf "$platform_module"
	rm -rf "$refresh_module"
	mkdir -p "$refresh_module"
	cat >"$refresh_module/README.md" <<'EOF'
# Refresh Smoke

## Prerequisites

```bash
test -n "$HOME"
```

## Install

```bash
printf 'install\n'
```

## Post Install

```bash
printf 'post-install\n'
```

## Update

```bash
printf 'update\n'
```

## Configure

```bash
printf 'configure\n'
```
EOF

	"$tilde" plan --repo "$repo" --allow-dirty --mode align --platform linux --host smoke >"$align_plan_json"
	"$tilde" plan --repo "$repo" --mode refresh --platform linux --host smoke >"$refresh_plan_json"
	"$tilde" plan --repo "$repo" --mode refresh --scope full --platform linux --host smoke >"$full_refresh_plan_json"
	"$tilde" plan --repo "$repo" --mode upgrade --platform linux --host smoke >"$upgrade_plan_json"

	ALIGN_PLAN_JSON=$align_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("ALIGN_PLAN_JSON")))
		abort "wrong align mode" unless plan.fetch("mode") == "align"
		abort "align should not have scope" unless plan["scope"].nil?
		abort "align should not advance anchors" if plan.fetch("target").fetch("converges")
		abort "align should not include package actions" if plan.fetch("actions").any? { |action| action.fetch("kind") == "package" }
		abort "align should not include section actions" if plan.fetch("actions").any? { |action| %w[section manual].include?(action.fetch("kind")) }
		abort "align should include link actions" unless plan.fetch("actions").any? { |action| action.fetch("kind") == "link" }
		abort "align should include file materialization actions" unless plan.fetch("actions").any? { |action| %w[copy seed reset].include?(action.fetch("kind")) }
		abort "align modules should not install packages" if plan.fetch("modules").any? { |mod| mod.fetch("packages_to_install").any? }
		abort "align modules should not keep special sections" if plan.fetch("modules").any? { |mod| mod.fetch("special_sections").any? }
	'

	REFRESH_PLAN_JSON=$refresh_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("REFRESH_PLAN_JSON")))
		abort "wrong refresh mode" unless plan.fetch("mode") == "refresh"
		abort "wrong refresh scope" unless plan.fetch("scope") == "fast"
		abort "refresh should advance anchors after success" unless plan.fetch("target").fetch("converges")
		abort "refresh should not create core links" unless plan.fetch("core").fetch("links_to_create").empty?
		abort "refresh should not write fallback home entrypoints" unless plan.fetch("core").fetch("home_entrypoints_to_write").empty?
		neovim = plan.fetch("modules").find { |mod| mod.fetch("name") == "neovim" }
		abort "missing neovim module" unless neovim
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module" unless git
		abort "refresh should include declared packages" unless git.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:git" }
		abort "refresh should include declared links" if git.fetch("links_to_create").empty?
		linux = plan.fetch("modules").find { |mod| mod.fetch("name") == "linux" }
		abort "missing linux module" unless linux
		abort "missing fast brew refresh" unless linux.fetch("packages_to_refresh").any? { |pkg| pkg.fetch("value") == "brew:*" }
		abort "refresh should not include per-package brew refresh" if plan.fetch("modules").any? { |mod| mod.fetch("packages_to_refresh").any? { |pkg| pkg.fetch("value") == "brew:neovim" } }
		abort "fast refresh should include update section" unless neovim.fetch("special_sections").key?("Update")
		smoke = plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-refresh-smoke" }
		abort "missing refresh smoke module" unless smoke
		abort "refresh should include prerequisite section" unless smoke.fetch("special_sections").key?("Prerequisites")
		abort "refresh should include install section" unless smoke.fetch("special_sections").key?("Install")
		abort "refresh should include post-install section" unless smoke.fetch("special_sections").key?("Post Install")
		abort "refresh should include update section" unless smoke.fetch("special_sections").key?("Update")
		abort "refresh should include configure section" unless smoke.fetch("special_sections").key?("Configure")
		actions = plan.fetch("actions")
		smoke_indexes = %w[Prerequisites Install Post\ Install Update Configure].to_h do |name|
			[name, actions.index { |action| action.fetch("module_id") == "public/zz-refresh-smoke" && action.fetch("name", nil) == name }]
		end
		abort "refresh should include all smoke section actions" if smoke_indexes.values.any?(&:nil?)
		abort "refresh should run install before update" unless smoke_indexes.fetch("Install") < smoke_indexes.fetch("Update")
		abort "refresh should run update before configure" unless smoke_indexes.fetch("Update") < smoke_indexes.fetch("Configure")
	'

	FULL_REFRESH_PLAN_JSON=$full_refresh_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("FULL_REFRESH_PLAN_JSON")))
		abort "wrong full refresh mode" unless plan.fetch("mode") == "refresh"
		abort "wrong full refresh scope" unless plan.fetch("scope") == "full"
		javascript = plan.fetch("modules").find { |mod| mod.fetch("name") == "javascript" }
		abort "missing javascript module" unless javascript
		abort "missing managed npm refresh" unless javascript.fetch("packages_to_refresh").any? { |pkg| pkg.fetch("value") == "npm:@biomejs/biome" }
		neovim = plan.fetch("modules").find { |mod| mod.fetch("name") == "neovim" }
		abort "missing neovim module" unless neovim
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module" unless git
		abort "full refresh should include declared packages" unless git.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:git" }
		abort "full refresh should include declared links" if git.fetch("links_to_create").empty?
		abort "missing neovim update section" unless neovim.fetch("special_sections").key?("Update")
		smoke = plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-refresh-smoke" }
		abort "missing full refresh smoke module" unless smoke
		abort "full refresh should include prerequisite section" unless smoke.fetch("special_sections").key?("Prerequisites")
		abort "full refresh should include install section" unless smoke.fetch("special_sections").key?("Install")
		abort "full refresh should include post-install section" unless smoke.fetch("special_sections").key?("Post Install")
		abort "full refresh should include update section" unless smoke.fetch("special_sections").key?("Update")
		abort "full refresh should include configure section" unless smoke.fetch("special_sections").key?("Configure")
	'

	UPGRADE_PLAN_JSON=$upgrade_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("UPGRADE_PLAN_JSON")))
		abort "wrong upgrade mode" unless plan.fetch("mode") == "upgrade"
		abort "wrong upgrade scope" unless plan.fetch("scope") == "full"
		abort "upgrade should advance anchors after success" unless plan.fetch("target").fetch("converges")
		linux = plan.fetch("modules").find { |mod| mod.fetch("name") == "linux" }
		abort "missing linux module" unless linux
		abort "upgrade should include fast brew refresh" unless linux.fetch("packages_to_refresh").any? { |pkg| pkg.fetch("value") == "brew:*" }
		abort "upgrade should include broad cask upgrade" unless linux.fetch("packages_to_upgrade").any? { |pkg| pkg.fetch("value") == "cask:*" }
		abort "upgrade should include broad flatpak upgrade" unless linux.fetch("packages_to_upgrade").any? { |pkg| pkg.fetch("value") == "flatpak:*" }
		javascript = plan.fetch("modules").find { |mod| mod.fetch("name") == "javascript" }
		abort "missing javascript module" unless javascript
		abort "upgrade should include managed npm refresh" unless javascript.fetch("packages_to_refresh").any? { |pkg| pkg.fetch("value") == "npm:@biomejs/biome" }
		neovim = plan.fetch("modules").find { |mod| mod.fetch("name") == "neovim" }
		abort "missing neovim module" unless neovim
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module" unless git
		abort "upgrade should include declared packages" unless git.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:git" }
		abort "upgrade should include declared links" if git.fetch("links_to_create").empty?
		abort "upgrade should include update section" unless neovim.fetch("special_sections").key?("Update")
		smoke = plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-refresh-smoke" }
		abort "missing upgrade smoke module" unless smoke
		abort "upgrade should include prerequisite section" unless smoke.fetch("special_sections").key?("Prerequisites")
		abort "upgrade should include install section" unless smoke.fetch("special_sections").key?("Install")
		abort "upgrade should include post-install section" unless smoke.fetch("special_sections").key?("Post Install")
		abort "upgrade should include update section" unless smoke.fetch("special_sections").key?("Update")
		abort "upgrade should include configure section" unless smoke.fetch("special_sections").key?("Configure")
		actions = plan.fetch("actions")
		update_indexes = actions.each_index.select { |index| actions.fetch(index).fetch("name", nil) == "Update" }
		upgrade_indexes = actions.each_index.select { |index| actions.fetch(index).fetch("operation", nil) == "upgrade" }
		abort "upgrade should include update actions" if update_indexes.empty?
		abort "upgrade should include package upgrade actions" if upgrade_indexes.empty?
		abort "upgrade actions should run after full refresh" unless upgrade_indexes.min > update_indexes.max
	'

	NORMAL_PLAN_JSON=$normal_plan_json EXTRA_PLAN_JSON=$extra_plan_json MACOS_PLAN_JSON=$macos_plan_json PRIVATE_PLAN_JSON=$private_plan_json PRIVATE_EXTRA_PLAN_JSON=$private_extra_plan_json PRIVATE_MACOS_PLAN_JSON=$private_macos_plan_json PRIVATE_MACOS_EXTRA_PLAN_JSON=$private_macos_extra_plan_json ALIGN_PLAN_JSON=$align_plan_json REFRESH_PLAN_JSON=$refresh_plan_json FULL_REFRESH_PLAN_JSON=$full_refresh_plan_json UPGRADE_PLAN_JSON=$upgrade_plan_json ruby -rjson -ropen3 -e '
		%w[
			NORMAL_PLAN_JSON
			EXTRA_PLAN_JSON
			MACOS_PLAN_JSON
			PRIVATE_PLAN_JSON
			PRIVATE_EXTRA_PLAN_JSON
			PRIVATE_MACOS_PLAN_JSON
			PRIVATE_MACOS_EXTRA_PLAN_JSON
			ALIGN_PLAN_JSON
			REFRESH_PLAN_JSON
			FULL_REFRESH_PLAN_JSON
			UPGRADE_PLAN_JSON
		].filter_map { |name| ENV[name] }.select { |path| File.exist?(path) }.each do |path|
			plan = JSON.parse(File.read(path))
			plan.fetch("modules").each do |mod|
				mod.fetch("special_sections").each do |name, section|
					section.fetch("bash_blocks").each_with_index do |block, index|
						_stdout, stderr, status = Open3.capture3("bash", "-n", stdin_data: block)
						next if status.success?

						abort "invalid bash block in #{mod.fetch(%q[name])} #{name} ##{index + 1}: #{stderr}"
					end
				end
			end
		end
	'

	repair_repo=$(mktemp -d)
	cleanup_repair_repo=$repair_repo
	cp -a "$repo/." "$repair_repo"
	head=$(git -C "$repair_repo" rev-parse HEAD)
	cat >"$XDG_STATE_HOME/tilde/state.yml" <<EOF
protocol: tilde/v1
public: $repair_repo
applied:
  level: normal
  platform: linux
  public: $head
EOF

	"$tilde" plan --repo "$repair_repo" --allow-dirty --mode repair --platform linux --host smoke-repair >"$repair_plan_json"

	REPAIR_PLAN_JSON=$repair_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("REPAIR_PLAN_JSON")))
		abort "wrong repair mode" unless plan.fetch("mode") == "repair"
		abort "repair should advance anchors after success" unless plan.fetch("target").fetch("converges")
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module in repair plan" unless git
		abort "git should be repaired" if git.fetch("skipped")
		abort "repair should include git packages" unless git.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:git" }
		abort "repair should include git links" if git.fetch("links_to_create").empty?
		mc = plan.fetch("modules").find { |mod| mod.fetch("name") == "mc" }
		abort "missing mc module in repair plan" unless mc
		abort "repair must not skip mc from state" if mc.fetch("skipped")
		abort "repair should include mc file materializations" if mc.fetch("copies_to_create").empty? || mc.fetch("seeds_to_create").empty?
		abort "repair should not include update sections" if plan.fetch("modules").any? { |mod| mod.fetch("special_sections").key?("Update") }
		abort "repair should not include update actions" if plan.fetch("actions").any? { |action| action.fetch("name", nil) == "Update" }
	'

	echo "plan smoke ok"
}

main "$@"
