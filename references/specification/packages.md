# Tilde Packages

## Package Installation

Group package installs by package type, present commands in the plan, and run them only after confirmation. Package
removal is never inferred from removed frontmatter entries.

Installation commands:

- `brew:<name>`: `brew install <name>`
- `cask:<name>`: `brew install --cask <name>`
- `deb:<name>`: `sudo apt install -y <name>`; run `sudo apt update` first when the package index may be stale. In
  non-interactive scripts, prefer `sudo apt-get install -y <name>`.
- `npm:<name>`: `bun install -g <name>`
- `gem:<name>`: `gem install --user-install --no-document <name>` unless local RubyGems config already routes installs
  to a user-writable gem home. Do not use `sudo gem install`.
- `egg:<name>`: `uv tool install <name>`. If the package does not expose the expected executable, inspect package docs
  and use a module README special section for package-specific flags such as `--with`.
- `flatpak:<app-id>`: conditionally install only on graphical targets with `flatpak install --user flathub <app-id>`,
  unless the module explicitly requires system-wide Flatpak install. The `graphical` condition is always true on macOS,
  true on Linux only when `systemctl get-default` is `graphical.target`, and false elsewhere.
- `scoop:<name>`: `scoop install <name>`
- `github:<owner>/<repo>`: inspect official release metadata with the GitHub API, GitHub MCP, or `gh release` commands.
  Select the asset that matches target platform and architecture, download to a temp directory, verify checksum or
  provenance when provided, extract it, and copy executables to `~/.local/bin`. If asset or executable layout is
  ambiguous, ask before installing.
- `skill:<source>`: install an agent skill from a Git-backed source. Accepted scalar sources include
  `github.com/<owner>/<repo>` and full Git URLs. The source repository contains the skill at its root; the skill name is
  the source repository basename; and the target is `~/.agents/skills/<name>`. If the target is missing, clone the
  source. If the target exists and is not a matching Git checkout, report a proposal-time conflict.

For `github` assets, prefer official release metadata over scraping HTML:

```bash
gh release view --repo OWNER/REPO --json tagName,assets
gh release download --repo OWNER/REPO --pattern 'PATTERN'
```

## Package Updates

Default update scope is managed packages only: update only package entries present in the active provisioning plan, one
package at a time or grouped by explicit package names. Do not run package-manager-wide upgrade commands unless the user
explicitly asks for a full/global update.

Before managed updates, run metadata refresh commands at most once per package manager represented in the confirmed
update set:

- `brew update`
- `sudo apt update`
- `scoop update`
- `flatpak update --appstream`

Managed update commands:

- `brew:<name>`: `brew upgrade <name>`
- `cask:<name>`: `brew upgrade --cask <name>`. If the cask is excluded from normal upgrades because it uses
  `version :latest` or self-updates, use `brew upgrade --cask --greedy <name>` only after calling out that extra scope.
- `deb:<name>`: `sudo apt-get install --only-upgrade -y <name>` after `sudo apt update`. If the package may not be
  installed yet, treat it as an install action.
- `npm:<name>`: `bun update -g <name>`
- `gem:<name>`: `gem update --user-install --no-document <name>`. Do not use bare `gem update`.
- `egg:<name>`: `uv tool upgrade <name>`. Use `uv tool install <name>` when changing version constraints or install
  flags.
- `flatpak:<app-id>`: conditionally run `flatpak update --user <app-id>` for per-user installs created by Tilde when
  the `graphical` condition is met.
- `scoop:<name>`: run `scoop update` first, then `scoop update <name>`.
- `github:<owner>/<repo>`: inspect latest release assets again, compare with the installed binary when possible, and
  replace the executable only after selecting the matching asset.
- `skill:<source>`: fetch the matching Git checkout and update with a non-destructive fast-forward-only merge. Dirty
  targets block automatic updates. Put any nonstandard Tilde skill update behavior in the owning module's `README.md`
  body instead of expanding `skill:` into a broad skill-management schema.
