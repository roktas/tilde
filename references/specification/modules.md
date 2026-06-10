# Tilde Modules

## Data Repository Layout

A public home data repository commonly looks like this. Private companion repositories use the same module rules but
may contain private policy and modules.

```text
.
  misc/
    README.md
  linux/
    README.md
  linux-/
    README.md
  macos/
    README.md
  home/
    README.md
    AGENTS.md
  git/
    README.md
    config
    ignore
    hooks/
    bin/
  agents/
    README.md
    skills/
  AGENTS.md
```

Repository-local `.agents/state/` is task/checkpoint/scratch state for agent work. It is not the canonical deployment
state for a managed host.

## Module README

A module `README.md` has optional YAML frontmatter and a Markdown body. Modules without explicit provisioning config may
omit frontmatter entirely. Missing `all` and platform keys are treated as empty maps.

Example:

````markdown
---
all:
  links:
    config: ~/.config/git/config
    ignore: ~/.config/git/ignore
    hooks/: ~/.config/git/hooks
    bin/: ~/.local/bin
  packages:
    - foo-bar
    - cask:foo-baz
    - deb:baz
    - npm:qux
    - gem:fred
    - egg:waldo
    - flatpak:org.foo.bar
    - github:user/project
    - skill:github.com/roktas/tilde
  level: normal
  hosts:
    - hostname
macos:
  links:
    bin/: ~/.local/bin
windows: ~
---

# Foo

Foo is bla bla.

## Install

```bash
brew install foo-qux
```
````

### Frontmatter

Frontmatter is a two-level map. The first level contains platform scopes. The second level contains links, copies,
packages, level, and an optional host filter.

First-level keys:

- Valid scopes are `all`, `linux`, `macos`, and `windows`.
- For the active host, start with `all`, then shallow-merge the active platform scope when present.
- Map values such as `links` and `copies` are shallow-merged one level deep.
- List and scalar values such as `packages` and `level` are replaced by the platform value when present.
- Nested maps are not deep-merged.
- If a root module has no `all` key and only platform keys, the module is excluded unless the active platform key exists.
  This also prevents body sections from running on the wrong platform.
- A platform scope may be YAML null (`macos: ~`). This selects the module for that platform without adding platform
  frontmatter actions.

Second-level keys:

**`links`** maps module-relative sources to symlink targets. Sources normally live in the module directory. Sources may
use `../` for shared files elsewhere in the repository, but normalized sources must not escape the repository. A target
may be a string or a list of strings. Use a list when one source must be linked to multiple targets.

If the source key does not end in `/`, the source file or directory itself is symlinked to the target. If the source key
ends in `/`, the link uses fan-in semantics: each direct child of the source directory is linked into the target
directory with the same basename. For example, `bin/: ~/.local/bin` links `bin/foo` to `~/.local/bin/foo` and `bin/bar`
to `~/.local/bin/bar`.

If a link target already exists, the provisioning action replaces it with the module source after confirmation. This is
intentionally aggressive; preserve local target changes before provisioning.

**`copies`** maps module-relative sources to physical copy targets. Sources must not escape the repository. Missing
target parent directories are created. Directory sources are copied recursively. Existing targets are replaced after
confirmation. Copy targets removed from frontmatter are not removed unless the user explicitly asks for copy removal.

**`packages`** is a flat YAML list of `[package-type:]package-name` strings. Do not nest package types as mapping keys;
use `gemini-cli` or `brew:gemini-cli`, not `brew: [gemini-cli]`.

Valid package types are `brew`, `cask`, `deb`, `npm`, `gem`, `egg`, `flatpak`, `scoop`, `github`, and `skill`.

Package type prefixes do not imply platform scope. In particular, `cask:` means Homebrew cask install behavior, not
macOS-only intent; express OS support with the enclosing `all`, `linux`, `macos`, or `windows` scope.

When no package type is provided, Linux and macOS default to `brew`; Windows defaults to `scoop`. For ordinary Homebrew
formulae in Linux, macOS, or shared scopes, use the bare package name instead of a redundant `brew:` prefix. `deb`
installs are system-wide through `sudo`. Other package types are installed user-wide through their package managers.
Prefer `bun` for `npm` packages and `uv` for `egg` Python tools. `github` packages are installed from release assets,
with executables placed in `~/.local/bin`. `skill` packages install agent skills from Git-backed sources into
`~/.agents/skills`.

If `packages` is missing, the module is virtual and installs no packages. Add package names explicitly for modules that
install packages. `packages: []` is valid but usually unnecessary.

Package management defaults to installation only. Packages removed from frontmatter are not removed unless the user
explicitly asks for package removal.

Most `packages` declarations are unconditional plan-time declarations. If package installation depends on runtime state,
put a guarded command in a special README section such as `Install` or `Preinstall` instead. If the condition is not
met, the command may exit `0` as an intentional no-op.

Flatpak package declarations are the exception: `flatpak:<app-id>` actions always carry the `graphical` condition and
are ignored when that condition is not met. `graphical` is always true on macOS, true on Linux only when
`systemctl get-default` is `graphical.target`, and false elsewhere. Keep session checks such as `DISPLAY`,
`WAYLAND_DISPLAY`, and `XDG_CURRENT_DESKTOP` for commands that truly require an active GUI session, such as `gsettings`,
MIME association, or launching GUI programs.

**`level`** is the provisioning scope level. Valid values are `minimal`, `normal`, and `extra`. The default is `normal`.
Plan selection uses threshold semantics: `minimal` includes only `minimal`; `normal` includes `minimal` and `normal`;
`extra` includes all three. Use `minimal` for the smallest useful base and `extra` for heavier optional or personal
tools.

**`hosts`** is an optional host filter. Entries match the short host name derived from `hostname -f`.

### Body

The README body is agent instruction text. Some headings are conventional special sections, documented under
Provisioning.

If a special section contains only `bash` fenced blocks and no other instruction text, the blocks are run in written
order after confirmation.

Special sections may contain lower-level headings such as `### GNOME`. These headings group literate instructions and
do not create new special-section semantics.

README bodies may use platform scopes: `## All Platforms`, `## Linux`, `## MacOS`, and `## Windows`. Inside such scopes,
write special sections one level lower, such as `### Install`. The active plan selects `All Platforms` and the active
platform only. Top-level sections such as `## Install` remain valid and are treated as all-platform sections. When a
top-level special section and a scoped special section share the same name, their bodies are concatenated in document
order.

Module body commands may assume the tools installed by earlier modules in provisioning order, especially the active
platform module and its variant. Prefer placing shared command-line tool dependencies in those earlier modules so
later module instructions stay direct and do not need to rediscover their prerequisites.

The harness does not interpret a special `Precondition` section, fenced-block metadata, or custom skip exit codes.
Runtime guards belong inside the command block. Exit-code semantics are plain: `0` means success or intentional no-op;
non-zero means failure.

Commands run only after confirmation. If the user gives explicit bulk approval at the start of provisioning, the agent
may avoid repeated confirmations for that run.
