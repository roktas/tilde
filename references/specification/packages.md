# Tilde Packages

## Package Installation

Group package installs by package type, present commands in the plan, and run them only after confirmation. Package
removal is never inferred from removed frontmatter entries.

The executor may use a cheap installed-package snapshot before running install actions for package managers that support
fast local listing. This is a best-effort optimization, not a desired-state source and not a planner input. Take the
snapshot once per apply run and package type, skip only exact installed-token matches, and report those actions as
`unchanged`. If the snapshot command is missing, fails, or cannot answer the exact token question, run the normal
idempotent install command. Do not infer aliases, virtual packages, providers, replacements, or package validity from
the snapshot.

Cheap snapshot examples:

- Homebrew formulae: `brew list --formula -1`.
- Homebrew casks: `brew list --cask -1`.
- Deb packages: `dpkg-query -W -f='${binary:Package}\n'`.

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
  ambiguous, report `notok` or ask before installing. Non-interactive `bin/apply` may only install an unambiguous
  matching asset; otherwise the module should use README instructions for package-specific choices.
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

Update scope is explicit and ordered:

```text
update < update full < upgrade
```

Plain `update` uses the fast update path. It must not update every managed package declaration one by one. It reconciles
desired state, then runs normal broad updates for active system package managers. This fast path is intentionally
allowed to affect packages outside the Tilde-managed set when the active package manager's normal upgrade command is
global.

`update full` includes the fast update path, then refreshes managed non-system package declarations and selected module
`Update` sections. It remains bounded by Tilde-managed declarations except for the fast system package-manager step it
inherits from plain `update`.

`upgrade` includes `update full`, then runs broad or aggressive package-manager upgrades after explicit confirmation.
Its proposal must say that packages not declared by Tilde may be affected.

Fast system package-manager updates:

- Homebrew is active when `brew` is available on the target or the active plan contains `brew:<name>` or `cask:<name>`.
  Run `brew update`, then `brew upgrade`. Do not use `--greedy` in plain `update` or `update full`.
- Apt is active on Linux when `apt-get` is available, even if no `deb:<name>` package declaration is present. Run
  `sudo apt-get update`, then `sudo apt-get upgrade -y`.
- Scoop is active on Windows when `scoop` is available or the active plan contains `scoop:<name>`. Run `scoop update`,
  then `scoop update *`.

Do not fail fast update merely because one supported system package manager is unavailable on a platform where another
active system package manager can be updated. Report unavailable managers when their absence prevents a requested
package action.

Full managed non-system updates:

- `npm:<name>`: `bun update -g <name>`
- `gem:<name>`: `gem update --user-install --no-document <name>`. Do not use bare `gem update`.
- `egg:<name>`: `uv tool upgrade <name>`. Use `uv tool install <name>` when changing version constraints or install
  flags.
- `flatpak:<app-id>`: conditionally run `flatpak update --user <app-id>` for per-user installs created by Tilde when
  the `graphical` condition is met. Do not update all Flatpaks during `update full`.
- `github:<owner>/<repo>`: inspect latest release assets again, compare with the installed binary when possible, and
  replace the executable only after selecting the matching asset. Non-interactive `bin/apply` must not guess when the
  matching asset or executable is ambiguous.
- `skill:<source>`: fetch the matching Git checkout and update with a non-destructive fast-forward-only merge. Dirty
  targets block automatic updates. Put any nonstandard Tilde skill update behavior in the owning module's `README.md`
  body instead of expanding `skill:` into a broad skill-management schema.

Broad or aggressive `upgrade` examples:

- Homebrew casks that normal `brew upgrade` skips may use `brew upgrade --cask --greedy` only after the proposal calls
  out the wider cask scope.
- Apt may use `sudo apt-get full-upgrade -y` only after the proposal calls out that packages may be installed, removed,
  or held differently than a normal upgrade.
- Flatpak may run `flatpak update -y --user` for all per-user Flatpaks only when the graphical condition is met and the
  proposal calls out that unmanaged apps may be affected.
- Scoop may use package-manager-wide update behavior beyond the active Tilde declarations after the proposal calls out
  that unmanaged apps may be affected.
