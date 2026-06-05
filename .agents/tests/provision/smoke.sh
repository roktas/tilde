#!/usr/bin/env bash

set -Eeuo pipefail
[[ -z ${TRACE:-} ]] || set -x
unset CDPATH

cleanup_dirty_module=
cleanup_extra_module=
cleanup_platform_module=
cleanup_repair_repo=
cleanup_target_module=
cleanup_tmpdir=

# ------------------------------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------------------------------

cleanup() {
	rm -rf "$cleanup_dirty_module" "$cleanup_extra_module" "$cleanup_platform_module" "$cleanup_target_module"
	[[ -z $cleanup_repair_repo ]] || rm -rf "$cleanup_repair_repo"
	[[ -z $cleanup_tmpdir ]] || rm -rf "$cleanup_tmpdir"
}

# ------------------------------------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------------------------------------

main() {
	local dirty_module
	local dirty_plan_err
	local extra_module
	local extra_plan_json
	local head
	local invalid_plan_err
	local invalid_plan_json
	local macos_plan_json
	local normal_plan_json
	local platform_module
	local plan
	local plan_json
	local private_macos_plan_json
	local private_plan_json
	local private_repo
	local refresh_plan_json
	local repair_repo=
	local repair_plan_json
	local repo
	local script_dir
	local skill_root
	local target_module
	local target_plan_json
	local tmpdir

	script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" >/dev/null && pwd)
	skill_root=$(cd -- "$script_dir/../../.." >/dev/null && pwd)
	plan=$skill_root/bin/plan
	repo=${REPO_ROOT:-$(cd -- "$skill_root/../home" >/dev/null && pwd)}
	private_repo=${PRIVATE_REPO_ROOT:-}
	if [[ -z $private_repo && -d $repo/../home- ]]; then
		private_repo=$(cd -- "$repo/../home-" >/dev/null && pwd)
	fi
	dirty_module=$repo/zz-dirty-smoke
	extra_module=$repo/zz-extra-smoke
	platform_module=$repo/zz-platform-smoke
	target_module=$repo/zz-target-smoke
	cleanup_dirty_module=$dirty_module
	cleanup_extra_module=$extra_module
	cleanup_platform_module=$platform_module
	cleanup_target_module=$target_module

	trap cleanup EXIT HUP INT QUIT TERM

	cd "$repo"

	tmpdir=$(mktemp -d)
	cleanup_tmpdir=$tmpdir
	export XDG_STATE_HOME=$tmpdir/state
	dirty_plan_err=$tmpdir/dirty-plan.err
	extra_plan_json=$tmpdir/extra-plan.json
	invalid_plan_err=$tmpdir/invalid-package-plan.err
	invalid_plan_json=$tmpdir/invalid-package-plan.json
	macos_plan_json=$tmpdir/macos-plan.json
	normal_plan_json=$tmpdir/normal-plan.json
	plan_json=$tmpdir/plan.json
	private_macos_plan_json=$tmpdir/private-macos-plan.json
	private_plan_json=$tmpdir/private-plan.json
	refresh_plan_json=$tmpdir/refresh-plan.json
	repair_plan_json=$tmpdir/repair-plan.json
	target_plan_json=$tmpdir/target-plan.json

	export GIT_CONFIG_GLOBAL=${GIT_CONFIG_GLOBAL:-$tmpdir/gitconfig}

	git config --global --add safe.directory "$repo"
	[[ -z $private_repo ]] || git config --global --add safe.directory "$private_repo"

	ruby -c "$plan"

	rm -rf "$dirty_module"
	mkdir -p "$dirty_module"
	cat >"$dirty_module/README.md" <<'EOF'
# Dirty Guard Smoke
EOF

	if "$plan" --repo "$repo" >"$plan_json" 2>"$dirty_plan_err"; then
		echo "expected dirty worktree guard to fail" >&2
		exit 1
	fi

	grep -q "Dirty worktree" "$dirty_plan_err"
	rm -rf "$dirty_module"

	"$plan" --repo "$repo" --allow-dirty --platform linux --host smoke >"$plan_json"

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
		abort "legacy home-entrypoint action kind leaked" if actions.any? { |action| action.fetch("kind") == "home-entrypoint" }
		abort "missing manual linux install action" unless actions.any? { |action| action.fetch("kind") == "manual" && action.fetch("module_id") == "public/linux" && action.fetch("name") == "Install" }
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
		misc = plan.fetch("modules").find { |mod| mod.fetch("name") == "misc" }
		abort "missing misc module" unless misc
		abort "misc module should run alphabetically" unless plan.fetch("modules").map { |mod| mod.fetch("name") }.index("misc") > plan.fetch("modules").map { |mod| mod.fetch("name") }.index("markdown")
		abort "misc module should install shared tools" unless misc.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:zoxide" }
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
		abort "missing mc.ini copy" unless mc.fetch("copies_to_create").any? { |copy| copy.fetch("target") == "~/.config/mc/ini" }
		abort "gnome module should not be planned" if plan.fetch("modules").any? { |mod| mod.fetch("name") == "gnome" }
	'

	if [[ -n $private_repo ]]; then
		"$plan" --repo "$private_repo" --allow-dirty --platform linux --host smoke >"$private_plan_json"
		"$plan" --repo "$private_repo" --allow-dirty --platform macos --host smoke >"$private_macos_plan_json"

		PRIVATE_PLAN_JSON=$private_plan_json PRIVATE_MACOS_PLAN_JSON=$private_macos_plan_json ruby -rjson -e '
			linux = JSON.parse(File.read(ENV.fetch("PRIVATE_PLAN_JSON")))
			codex = linux.fetch("modules").find { |mod| mod.fetch("name") == "codex" }
			abort "missing private codex module" unless codex
			abort "missing linux codex-switcher package" unless codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "github:Lampese/codex-switcher" }
			abort "linux codex should not install codex cask" if codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:codex" }
			abort "codex should link shared wrapper bin" unless codex.fetch("links_to_create").any? { |link| link.fetch("source") == "bin/codex" && link.fetch("target") == "~/Dropbox/bin/all/codex" && link.fetch("fan_in") == true }
			abort "codex should link hooks into shared codex state" unless codex.fetch("links_to_create").any? { |link| link.fetch("source") == "hooks/shellcheck" && link.fetch("target") == "~/Dropbox/var/codex/hooks/shellcheck" && link.fetch("fan_in") == true }
			hook_action = linux.fetch("actions").find { |action| action.fetch("kind") == "link" && action.fetch("target") == "~/Dropbox/var/codex/hooks/shellcheck" }
			abort "missing codex hook action" unless hook_action
			abort "codex hook should use a relative Dropbox link value" unless hook_action.fetch("link_value") == "../../../src/home-/codex/hooks/shellcheck"
			abort "codex should use shared agent instructions" unless codex.fetch("special_sections").dig("Install", "body").include?("Dropbox/var/codex/AGENTS.md")
			abort "codex should not link skills under ~/.codex" if codex.fetch("links_to_create").any? { |link| link.fetch("target").start_with?("~/.codex/skills/") }
			dropignore = linux.fetch("modules").find { |mod| mod.fetch("name") == "dropignore" }
			abort "missing private dropignore module" unless dropignore
			abort "missing linux dropignore package" unless dropignore.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "github:mweirauch/dropignore" }
			opencode = linux.fetch("modules").find { |mod| mod.fetch("name") == "opencode" }
			abort "missing private opencode module" unless opencode
			abort "missing opencode package" unless opencode.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:opencode" }
			abort "opencode should not install aicommits package" if opencode.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:aicommits" }
			abort "opencode should use shared agent instructions" unless opencode.fetch("special_sections").dig("Install", "body").include?("Dropbox/var/opencode/config/AGENTS.md")
			abort "opencode should not link skills directly" if opencode.fetch("links_to_create").any? { |link| link.fetch("target").include?("/skills/") }

			macos = JSON.parse(File.read(ENV.fetch("PRIVATE_MACOS_PLAN_JSON")))
			macos_codex = macos.fetch("modules").find { |mod| mod.fetch("name") == "codex" }
			abort "missing macos codex module" unless macos_codex
			abort "missing macos codex cask" unless macos_codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "cask:codex" }
			abort "macos codex should not install codex-switcher release" if macos_codex.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "github:Lampese/codex-switcher" }
			macos_dropignore = macos.fetch("modules").find { |mod| mod.fetch("name") == "dropignore" }
			abort "missing macos dropignore module" unless macos_dropignore
			abort "missing macos dropignore rust package" unless macos_dropignore.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:rust" }
		'
	fi

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

	"$plan" --repo "$repo" --allow-dirty --platform linux --host smoke >"$target_plan_json"

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

	"$plan" --repo "$companion_public" --platform linux --host smoke >"$companion_plan_json"

	COMPANION_PLAN_JSON=$companion_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("COMPANION_PLAN_JSON")))
		abort "companion-owned home entrypoint should suppress fallback" unless plan.fetch("core").fetch("home_entrypoints_to_write").empty?
	'

	rm -rf "$extra_module"
	mkdir -p "$extra_module"
	cat >"$extra_module/README.md" <<'EOF'
---
all:
  level: extra
---

# Extra Smoke
EOF

	"$plan" --repo "$repo" --allow-dirty --platform linux --host smoke >"$normal_plan_json"
	"$plan" --repo "$repo" --allow-dirty --level extra --platform linux --host smoke >"$extra_plan_json"

	NORMAL_PLAN_JSON=$normal_plan_json EXTRA_PLAN_JSON=$extra_plan_json ruby -rjson -e '
		normal_plan = JSON.parse(File.read(ENV.fetch("NORMAL_PLAN_JSON")))
		extra_plan = JSON.parse(File.read(ENV.fetch("EXTRA_PLAN_JSON")))
		abort "extra module should not be planned at normal level" if normal_plan.fetch("modules").any? { |mod| mod.fetch("name") == "zz-extra-smoke" }
		linux_dash = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "linux-" }
		abort "missing linux dash variant at extra level" unless linux_dash
		abort "linux dash variant should follow linux" unless extra_plan.fetch("modules")[1].fetch("name") == "linux-"
		abort "calibre should be a guarded install section" unless linux_dash.fetch("special_sections").dig("Install", "body").include?("com.calibre_ebook.calibre")
		extra = extra_plan.fetch("modules").find { |mod| mod.fetch("name") == "zz-extra-smoke" }
		abort "missing extra module at extra level" unless extra
		abort "wrong extra module level" unless extra.fetch("level") == "extra"
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
		abort "missing virtualbox postinstall section" unless virtualbox.fetch("special_sections").key?("Postinstall")
		abort "ghostty should not be planned on linux" if extra_plan.fetch("modules").any? { |mod| mod.fetch("name") == "ghostty" }
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

```bash
echo all
```

## MacOS

### Install

```bash
echo macos
```
EOF

	"$plan" --repo "$repo" --allow-dirty --platform macos --host smoke >"$macos_plan_json"

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

	if "$plan" --repo "$repo" --allow-dirty --platform linux --host smoke >"$invalid_plan_json" 2>"$invalid_plan_err"; then
		echo "expected invalid package name guard to fail" >&2
		exit 1
	fi

	grep -q "Package name must not be empty" "$invalid_plan_err"

	rm -rf "$platform_module"

	"$plan" --repo "$repo" --mode refresh --platform linux --host smoke >"$refresh_plan_json"

	REFRESH_PLAN_JSON=$refresh_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("REFRESH_PLAN_JSON")))
		abort "wrong refresh mode" unless plan.fetch("mode") == "refresh"
		abort "refresh should not create core links" unless plan.fetch("core").fetch("links_to_create").empty?
		abort "refresh should not write fallback home entrypoints" unless plan.fetch("core").fetch("home_entrypoints_to_write").empty?
		neovim = plan.fetch("modules").find { |mod| mod.fetch("name") == "neovim" }
		abort "missing neovim module" unless neovim
		abort "refresh should not create links" unless neovim.fetch("links_to_create").empty?
		abort "missing neovim refresh package" unless neovim.fetch("packages_to_refresh").any? { |pkg| pkg.fetch("value") == "brew:neovim" }
		abort "missing neovim update section" unless neovim.fetch("special_sections").key?("Update")
	'

	NORMAL_PLAN_JSON=$normal_plan_json EXTRA_PLAN_JSON=$extra_plan_json MACOS_PLAN_JSON=$macos_plan_json PRIVATE_PLAN_JSON=$private_plan_json PRIVATE_MACOS_PLAN_JSON=$private_macos_plan_json REFRESH_PLAN_JSON=$refresh_plan_json ruby -rjson -ropen3 -e '
		%w[
			NORMAL_PLAN_JSON
			EXTRA_PLAN_JSON
			MACOS_PLAN_JSON
			PRIVATE_PLAN_JSON
			PRIVATE_MACOS_PLAN_JSON
			REFRESH_PLAN_JSON
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
	mkdir -p "$XDG_STATE_HOME/tilde/hosts/smoke-repair"
	head=$(git -C "$repair_repo" rev-parse HEAD)
	cat >"$XDG_STATE_HOME/tilde/hosts/smoke-repair/state.md" <<EOF
---
head: $head
done:
  git: notok
  mc: ok
---
EOF

	"$plan" --repo "$repair_repo" --allow-dirty --mode repair --platform linux --host smoke-repair >"$repair_plan_json"

	REPAIR_PLAN_JSON=$repair_plan_json ruby -rjson -e '
		plan = JSON.parse(File.read(ENV.fetch("REPAIR_PLAN_JSON")))
		abort "wrong repair mode" unless plan.fetch("mode") == "repair"
		git = plan.fetch("modules").find { |mod| mod.fetch("name") == "git" }
		abort "missing git module in repair plan" unless git
		abort "git should be repaired" if git.fetch("skipped")
		abort "repair should include git packages" unless git.fetch("packages_to_install").any? { |pkg| pkg.fetch("value") == "brew:git" }
		abort "repair should include git links" if git.fetch("links_to_create").empty?
		mc = plan.fetch("modules").find { |mod| mod.fetch("name") == "mc" }
		abort "missing mc module in repair plan" unless mc
		abort "mc should be skipped during repair" unless mc.fetch("skipped")
		abort "skipped repair module should not include copies" unless mc.fetch("copies_to_create").empty?
	'

	echo "provision smoke ok"
}

main "$@"
