# Tilde Spec

Tilde is an agent skill and control plane for home provisioning and workspace management. It operates on public and
private home data repositories, and it can provision the current machine or a remote machine reached over SSH. The
durable behavior lives here; skills and helpers implement this spec.

## Terms

- **Module**: a root directory that represents one application or provisioning unit.
- **Misc module**: the normal `misc` module for small shared declarations that do not deserve a focused module. It has
  no bootstrap role. If `misc-` exists, it is an `extra` module.
- **Platform module**: `linux`, `macos`, or `windows`. It defines generic platform behavior such as package-manager
  policy or platform defaults.
- **Platform variant**: `linux-`, `macos-`, or `windows-`. The active variant runs immediately after the active platform
  module. The trailing dash has no global meaning; the module README defines the local semantics.
- **Control plane**: the installed `tilde` skill, normally at `~/.agents/skills/tilde`. It owns prompt semantics,
  protocol references, helper commands, router templates, diagnostics, and validation.
- **Public data repository**: the user's public home repository, conventionally named `home`. It contains public-safe
  modules, shared agent assets, and desired state declarations.
- **Private data repository**: the optional private companion repository, conventionally named `home-`. It contains
  private modules, private policy, and preference-sensitive home behavior.
- **Host**: the short name derived from `hostname -f` by removing the trailing domain. For example, `kant.local` becomes
  `kant`.
- **Home**: the target user's home directory on the machine being managed. After deployment, Tilde's main user-facing
  surface is the home directory, not the repository checkout.
- **Home router**: the short Tilde-specific entrypoint installed at `~/AGENTS.md`. It routes agents to the installed
  Tilde skill and the configured public/private data repositories. Its template lives at `assets/AGENTS.md` in the
  installed skill.
- **Deployment**: applying Tilde's desired state to a local or remote host. Deployment is the user-facing operation that
  may include initialization, bootstrap/preflight, repository preparation, planning, installing links/copies/packages,
  and state update.
- **Provisioning**: the lower-level module operation performed during deployment: evaluating module frontmatter and
  README instructions, then installing packages and creating links or copies.
- **Managed surface**: files, directories, links, copies, packages, and deployment state that Tilde can explain from its
  active public/private repository definitions.
- **Proposal**: an agent-produced plan for a home-management action. A proposal describes intended reads, writes, moves,
  links, copies, or removals before any action is taken.
- **Deployment state**: runtime record for a host. Deployment state records module deployment results; home-management
  proposals are not written to deployment state.

## Model

- The installed skill is the control plane. User-specific home data and host runtime state do not live in the installed
  skill.
- Public and private data repositories declare their Tilde role in existing repository-facing files, preferably
  `AGENTS.md` YAML frontmatter:

  ```yaml
  ---
  tilde:
    protocol: tilde/v1
    role: public
    private: ../home-
  ---
  ```

  ```yaml
  ---
  tilde:
    protocol: tilde/v1
    role: private
    public: ../home
  ---
  ```

- Repository names such as `home` and `home-` are conventions only. Correctness comes from explicit repository
  identity and bounded discovery.
- Each module describes how to install or configure one application or virtual provisioning unit.
- Module names usually match the common application name and default package name. Exceptions belong in the module
  `README.md`.
- A module directory contains `README.md` and any files used during provisioning. README frontmatter is optional.
- Root modules are direct child directories of the active public/private data repository roots. Dot directories, `.git`,
  and `.agents` are excluded.
- A root directory is a module only when it contains `README.md`.
- Provisioning decisions are made after host deployment state is loaded.
- On fresh or underprovisioned hosts, run `bin/bootstrap` explicitly before normal provisioning when
  baseline tools are missing. Bootstrap is state-free and idempotent.
- Deployment uses provisioning modes internally. User-facing commands may say `deploy`, while lower-level module
  execution may use `apply`, `refresh`, `repair`, or `upgrade`.
- Normal plans process the active platform module first, the active platform variant second, and all other active root
  modules alphabetically. Inactive platform modules and inactive platform variants are excluded.
- Root modules may be platform-gated by defining only platform keys such as `linux:`.
- Deployment state for a host is written under `~/.local/state/tilde` by default.

## Paths

- In tracked repository files, write home paths with `~`; do not write expanded home paths.
- Use repository-relative or module-relative paths for files inside the active data repository or installed skill.
- Do not add machine-specific, user-specific, or local checkout-specific absolute filesystem paths to frontmatter,
  instructions, specs, notes, or scripts.

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

When no package type is provided, Linux and macOS default to `brew`; Windows defaults to `scoop`. `deb` installs are
system-wide through `sudo`. Other package types are installed user-wide through their package managers. Prefer `bun` for
`npm` packages and `uv` for `egg` Python tools. `github` packages are installed from release assets, with executables
placed in `~/.local/bin`. `skill` packages install agent skills from Git-backed sources into `~/.agents/skills`.

If `packages` is missing, the module is virtual and installs no packages. Add package names explicitly for modules that
install packages. `packages: []` is valid but usually unnecessary.

Package management defaults to installation only. Packages removed from frontmatter are not removed unless the user
explicitly asks for package removal.

`packages` is plan-time declaration only. The harness does not evaluate runtime conditions. If package installation
depends on runtime state, put a guarded command in a special README section such as `Install` or `Preinstall` instead.
If the condition is not met, the command may exit `0` as an intentional no-op.

GUI or desktop-host-dependent package installs also belong in guarded special-section commands, not in frontmatter
`packages`. Because SSH provisioning can target a desktop host without a GUI session, do not use `DISPLAY` or
`WAYLAND_DISPLAY` as the package-install guard. On Linux, prefer `systemctl get-default == graphical.target` for package
installs. Keep session checks such as `DISPLAY`, `WAYLAND_DISPLAY`, and `XDG_CURRENT_DESKTOP` for commands that truly
require an active GUI session, such as `gsettings`, MIME association, or launching GUI programs.

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

The harness does not interpret a special `Precondition` section, fenced-block metadata, or custom skip exit codes.
Runtime guards belong inside the command block. Exit-code semantics are plain: `0` means success or intentional no-op;
non-zero means failure.

Commands run only after confirmation. If the user gives explicit bulk approval at the start of provisioning, the agent
may avoid repeated confirmations for that run.

## Deployment State

Machine-specific runtime state lives outside the installed skill and outside the public/private data repositories by
default.

Preferred state root:

```text
~/.local/state/tilde
```

Suggested structure:

```text
~/.local/state/tilde/
  config.yml
  hosts/
    HOST/
      state.md
      last-plan.json
      last-apply.json
  remotes/
    HOST/
      state.md
```

`config.yml` records the local binding between the installed skill and the user's data repositories:

```yaml
protocol: tilde/v1
skill: ~/.agents/skills/tilde
public: ~/Dropbox/src/home
private: ~/Dropbox/src/home-
```

`private` may be omitted when the user has no private companion repository.

Host state frontmatter records enough provenance to explain what was applied:

- `host`: short host name.
- `date`: provisioning time.
- `skill`: installed skill path or version.
- `head`: public repository `HEAD` at provisioning time, retained for compatibility with current plan helpers.
- `public`: public repository path and commit.
- `private`: private repository path and commit when present.
- `done`: ordered map of provisioned module directories. Values are `ok`, `notok`, or `ignored`.

The deployment state body is optional. Use it for details that may help resolve future `notok` modules.

`last-plan.json` and `last-apply.json` are read-only status caches after provisioning. `status` may summarize managed
module, link, copy, and package counts from these files without regenerating a plan or checking live targets. If these
cache files are missing, `status` must say that managed-surface counts are unavailable instead of silently performing a
longer discovery pass.

For remote deployments, the target host's state under its own `~/.local/state/tilde` is authoritative. The controller
machine may keep a read-only mirror for status and history under `~/.local/state/tilde/remotes/HOST/`, but remote state
is not owned by the public/private data repositories.

Repository-local `.agents/state/` remains appropriate for local task state, checkpoints, logs, and development scratch.
It must not become the canonical deployment state for a user's host.

## Skill Installation and Updates

Tilde itself is installed and updated as a skill. External package-manager distribution is out of scope for this spec.

There are three lifecycle modes:

- **Bootstrap**: an external path installs enough agent runtime and Tilde skill to run `$tilde create`, `$tilde init`,
  or `$tilde deploy`.
- **Managed steady state**: the user's public/private home configuration keeps the installed Tilde skill current.
- **Development/local-current**: Tilde is already present on the machine, usually from a local checkout, and must not be
  reinstalled, downgraded, or self-updated unless the user explicitly asks for it.

Managing the Tilde skill must not create a bootstrapping loop. Deployment may require the skill to exist before public
and private data repositories have been installed.

The preferred managed form is a normal package entry in a home data module:

```yaml
---
all:
  packages:
    - skill:github.com/roktas/tilde
---
```

Local development may use ordinary links instead:

```yaml
---
all:
  links:
    ../tilde: ~/.agents/skills/tilde
---
```

Do not grow `skill:` into a broad skill-management schema. If a user needs different behavior for the Tilde skill, put
those instructions in the owning module's `README.md` body and let normal module special-section semantics handle it.

## Commands

Tilde commands are a prompt contract, not a strict shell CLI. Treat `$tilde [command] [subject...] [qualifiers...]` as a
compact way to express intent. The command name is stable; the subject and qualifiers may be natural language. Each
command defines its own semantics, and explicit arguments refine the target.

Bare `$tilde` means `update`. This default should handle the most common returning-user workflow after deployment:
reconcile desired state with the live home, then update managed external resources. It is still proposal-first and must
show the planned phases before making changes.

### Public Commands

`$tilde help` is the read-only public command reference. Start the output by showing the general format,
`$tilde <command> [<arguments>...]`. With no subject, it lists public commands with one-line action descriptions. With
one command subject, it shows detailed help for only that command. If the subject is not a public Tilde command, say
that no such public Tilde command exists, then behave like bare `$tilde help`.

Use this public action inventory for help output:

| Command | Action |
| --- | --- |
| `adopt` | Adopt an app, config, package, or path into public `home` or private `home-`. |
| `clean` | Propose conservative cleanup, including duplicate candidates when relevant. |
| `create` | Create public/private home repository skeletons. |
| `deploy` | Prepare a host and install desired state. |
| `doctor` | Diagnose deployment, repository, host, router, and managed-link health. |
| `help` | Show public commands or detailed help for one public command. |
| `init` | Register existing public/private repositories on this host. |
| `organize` | Propose organization changes, including archive moves when relevant. |
| `repair` | Retry failed install phases from recorded state. |
| `status` | Show a short deployment, home-router, and managed-surface summary. |
| `update` | Reconcile desired state, then refresh managed external resources. |
| `upgrade` | Run broad package-manager upgrades after explicit confirmation. |

After the table, show these short help notes:

- Detailed command help: `$tilde help <command>`
- Bare `$tilde` means `update`.

`apply`, `bootstrap`, `install`, `links`, `plan`, `refresh`, `archive`, and `dedupe` are not public prompt commands. Do
not show internal commands in ordinary help. Treat `plan`, `dry-run`, and `plan-only` as qualifiers on public commands
when the user asks to see the proposal without applying it.

Public command semantics:

- `help`: show the public Tilde command reference. Usage: `$tilde help [command]`.
- `create`: create or propose public/private home repository skeletons. With no explicit path, use default-location
  discovery before proposing writes.
- `init`: bind existing public/private repositories to the current host. It writes local config and the home router only
  after confirmation. It does not provision by itself.
- `deploy`: the main first-run and new-host journey command. It may orchestrate `create`, `init`,
  `internal.bootstrap`/preflight, planning, and `internal.install`, while preserving proposal-first behavior for each
  phase.
- `update`: run the returning-user maintenance flow: `internal.install`, then `internal.refresh`, after confirmation.
- `repair`: public wrapper over `internal.repair`.
- `upgrade`: run broad package-manager upgrades only on explicit request after describing scope.
- `status`: print a short read-only summary of configured public/private repositories, deployment state, and
  home-router facts, plus a concise managed-link/copy/package surface summary when cached state is available. It should
  prefer the installed `bin/status` helper when available so the agent can produce the summary with one read-only
  command. It must not perform broad diagnostics or regenerate plans by default. When full deployment state or status
  caches are missing, print a limited-status warning and suggest explicit next commands such as
  `$tilde status discover`, `$tilde doctor`, or `$tilde deploy`.
- `doctor`: diagnose host/home health, repository discovery, dirty worktrees, broken managed links, missing state, and
  Dropbox/Git consistency. It reports findings and suggestions, but it is not a whole-home audit.
- `adopt`: inspect a requested app, config, package identity, or explicit path; propose how to move it into public
  `home` or private `home-`; and wait for confirmation before any write.
- `clean`: propose conservative cleanup for selected home content. It may include duplicate candidates when relevant.
- `organize`: propose organization changes for selected home content. It may include archive moves when relevant.

Preference-sensitive commands:

- `clean`
- `organize`

These commands depend on personal policy. Before running them, read `home-/AGENTS.md` when available. If no private
policy exists, produce only conservative proposals or suggest creating private policy; do not infer aggressive cleanup or
organization rules from the public repository.

If a user asks for `dedupe`, interpret it as a `clean` request focused on duplicate candidates. If a user asks for
`archive`, interpret it as an `organize` request focused on archive moves. If a user asks for `links`, use `status` for
a read-only managed-surface summary or `doctor` for broken/stale/conflicting link diagnostics. If a user asks for
`plan`, use the nearest public command with a `dry-run` or `plan-only` qualifier.

`private` is not a built-in command. Use `home-` as the private companion repository and policy source.
Natural-language requests such as "adopt this into private" or "check the private repo" are valid qualifiers on other
commands.

### Fast Status

`status` is state-first and latency-sensitive. Its default path reads only cheap bounded sources:

- local Tilde config at `~/.local/state/tilde/config.yml`;
- host deployment state at `~/.local/state/tilde/hosts/HOST/state.md`;
- cached `last-plan.json` and `last-apply.json` when present;
- configured public/private repository summaries;
- home-router and installed-skill link facts.

Default `status` must not:

- run `bin/plan` to regenerate desired state;
- read every module `README.md` just to compute managed-surface counts;
- walk all managed targets to validate live links;
- query package managers, Dropbox, network remotes, or SSH targets unless the user explicitly requested that target.

If config, host state, or cache files are missing, return a partial summary and say that full deployment state was not
found. Long read-only fallback discovery is opt-in: use a qualifier such as `$tilde status discover` after telling the
user that Tilde will inspect module metadata and managed targets and may take noticeably longer. Broken-link, stale-link,
package, Dropbox, and consistency diagnostics belong to `doctor`, not default `status`.

### Internal Semantic Commands

Commands in the `internal.` namespace are internal semantic commands. They are not shown by ordinary `$tilde help`, are
not intended as user-facing entrypoints, and may be used by the skill/spec to define higher-level behavior.

For convenience while writing prompt-level specs or during Tilde development, `.name` may be accepted as shorthand for
`internal.name`. The dotted form signals private/internal semantics and leaves room for future namespaces.

Internal commands:

- `internal.bootstrap` or `.bootstrap`: run or plan the fresh-host bootstrap prelude.
- `internal.plan` or `.plan`: generate a provisioning plan.
- `internal.apply` or `.apply`: apply a provisioning plan.
- `internal.install` or `.install`: install desired state from public/private data repositories.
- `internal.refresh` or `.refresh`: refresh managed external resources.
- `internal.repair` or `.repair`: retry failed modules or failed installation phases from recorded state.

If a user explicitly requests an internal command, explain that it is internal and suggest the public command that covers
the same workflow, unless the user is developing Tilde itself.

### Command Relationships

```text
deploy = init + internal.bootstrap/preflight + internal.install
update = internal.install + internal.refresh
repair = public wrapper over internal.repair
```

The `dry-run`, `plan`, and `plan-only` qualifiers on public commands use `internal.plan` to produce a proposal and then
stop before applying changes.

CLI implementations should treat dotted command tokens as command names before path or extension interpretation, or
otherwise provide an unambiguous way to invoke internal commands during development.

### Proposal-First Rules

Repository creation, repository edits, router writes, state writes, package changes, file links, file copies,
remote-host actions, and destructive home-management actions must be proposal-first.

Proposals should name:

- target paths or hosts;
- what will be written, moved, removed, linked, copied, or installed;
- whether public or private data will be touched;
- whether runtime state will be updated;
- the expected blast radius.

### User Interaction

Use the agent runtime's clearest available interaction surface for confirmations, choices, and menus. Prefer native
structured confirmation or choice UI over raw terminal-style prompts such as `[Y/n]` when the runtime provides one. In
Codex, use the available structured user-input or AFALA-style tool when it is available and appropriate; in other agents,
use the equivalent native interaction mechanism when one exists.

If no structured UI is available, ask in plain language with explicit choices. Name the action, target host or path, and
blast radius. For multi-choice decisions, present a short numbered or bulleted list with one recommended option when
there is a safe default. For destructive or preference-sensitive actions, make the opt-in explicit; do not rely on a
single-letter default prompt.

Commands are proposal-first when they may change files, repositories, packages, state, router files, or remote hosts. A
proposal must describe the intended action and wait for confirmation before writes, moves, removals, package changes, or
repository edits.

## Home Entrypoint

Home entrypoint behavior covers the home router, bounded discovery from home, adoption, and preference-sensitive
home-management workflows.

### Data Repository Tilde Sections

Data repositories may provide Tilde-specific customization in existing Markdown bodies. The canonical anchor is a
second-level `## Tilde` heading. Tilde treats that section as data-layer policy and instructions, not as control-plane
specification.

Valid locations:

- root `AGENTS.md` in public and private data repositories;
- host `README.md` files for host-specific policy;
- module `README.md` files for module-local policy.

Do not put Tilde-specific data-layer policy in the home router. Root `README.md` files remain human-facing overviews
unless a future spec explicitly says otherwise.

Inside `## Tilde`, use typed third-level headings:

- `### Command: NAME`: instructions for a public command such as `adopt`, `clean`, or `deploy`, or for a custom command
  such as `custom.sync-host`. Data repositories must not define or override `internal.*` commands.
- `### Layout: PATH`: home or workspace layout facts for bounded discovery and preference-sensitive commands. `PATH`
  should be `~` or a `~`-relative path such as `~/Dropbox`.

Free text directly under `## Tilde` applies to all Tilde commands for that file's scope.

Example:

```markdown
## Tilde

### Command: adopt

Secrets, credentials, license files, host-specific values, private endpoints, account identifiers, and uncertain private
material belong in `home-` by default.

### Command: custom.sync-host

Synchronize the matching host directory in `home-` with `~/.<host>` on the remote machine. Use the private sync skill.
Never delete remote files by default.

### Layout: ~

Use runtime XDG user dirs for localized desktop directories. Do not infer aggressive cleanup rules from public data.

### Layout: ~/Dropbox

Source checkouts live under `~/Dropbox/src`.
```

Tilde section precedence is:

```text
control-plane spec
< public data root AGENTS.md
< private data root AGENTS.md
< host README.md
< module README.md
< explicit user request
```

More specific `Layout:` sections override or refine broader layout sections for the matching path. Data-layer
customization may add user policy and custom commands, but it must not weaken control-plane safety rules such as
proposal-first writes, bounded discovery, explicit destructive confirmation, and hiding internal commands from ordinary
help.

### Home Router

`assets/AGENTS.md` in the installed skill is the canonical home router template. Tilde deployment exposes it as
`~/AGENTS.md` through a core managed link or generated short router, outside module frontmatter. Keep the router short.
It routes agents; it does not carry detailed private preferences or full repository development policy.

The router should tell agents to:

- Treat the current directory as the user's home workspace when loaded from `~`.
- Resolve the installed Tilde skill from the resolved symlink target chain of `~/AGENTS.md` when possible. The normal
  target is `~/.agents/skills/tilde/assets/AGENTS.md`.
- Starting at the target file's parent directory, walk ancestors only until finding a directory that contains both
  `SKILL.md` and `references/spec.md`. That directory is the installed Tilde skill.
- Discover configured public/private home repositories from local Tilde state, router metadata, the current repository,
  or explicit paths.
- Discover sibling `home-` from `home` only when repository identity confirms it.
- Avoid recursive home scans by default.
- Read `home-/AGENTS.md` before preference-sensitive home commands when that file exists.
- Require explicit confirmation for destructive actions and for repository writes.

Do not put personal home layout policy in the public router. Layout policy such as localized directory names, cleanup
preferences, archive rules, and organization rules belongs in `home-/AGENTS.md` when private policy exists. Public
behavior may use cheap runtime detection, such as XDG user dirs, but must not assume a personal layout.

### Core Managed Links

Tilde deployment has core managed links that are not owned by any root module. They are planned before modules and use
the same confirmation and application semantics as normal link actions.

Core links:

- installed skill `assets/AGENTS.md` -> `~/AGENTS.md`

Do not place the home router link in the `agents` module. The `agents` module owns shared `~/.agents` assets; the home
router is a Tilde deployment invariant.

### Bounded Discovery

Do not recursively scan `$HOME` by default. Do not run `find $HOME`, `fd $HOME`, or equivalent broad recursive searches
unless the user explicitly requests a broad scan after the cost and scope are described.

Repository resolution order:

1. Explicit command arguments or options.
2. The current repository's `AGENTS.md` frontmatter, when it declares a Tilde role.
3. The local Tilde state config at `~/.local/state/tilde/config.yml`.
4. The home router at `~/AGENTS.md`.
5. Sibling discovery from an identified public or private repository, confirmed by `AGENTS.md` frontmatter.
6. Default location discovery for `create`, `init`, and first-run `deploy` only.
7. A clarification question.

Preferred command option names:

```text
--public PATH
--private PATH
--state-dir PATH
```

Positional convenience is allowed:

```text
$tilde create
$tilde init
$tilde init PUBLIC
$tilde init PUBLIC PRIVATE
```

With no explicit public path, `create` and `init` may use default-location discovery and then present a proposal before
creating or binding anything.

With one positional repository argument, the argument is the public data repository. The private data repository may be
discovered from frontmatter or a confirmed sibling path such as `home-`.

With two positional repository arguments, the first is public and the second is private.

Default repository locations are convenience only:

1. `~/Dropbox/src/home` and `~/Dropbox/src/home-` when `~/Dropbox/src` exists.
2. `~/.local/src/home` and `~/.local/src/home-` otherwise.

If a default path already exists, Tilde should inspect it for Tilde repository identity before using it. If it does not
exist, `create` or `deploy` may offer to create it after confirmation.

Use bounded discovery from:

- Existing public and private modules.
- Explicit paths provided by the user.
- Known managed targets from active module definitions.
- Cheap standard home metadata, such as XDG user dirs.
- Known application/config locations relevant to the requested subject.
- Cheap package or application metadata when available.

`status` is the exception to ordinary bounded-discovery fallback. If status state is incomplete, report the limitation
and stop unless the user explicitly requested a discovery qualifier or a diagnostic command.

Localized subjects such as `downloads`, `indirilenler`, or `İndirilenler` should be resolved through runtime detection
or private policy when possible. Hardcoded names are fallback only.

### Adoption

For `$tilde adopt SUBJECT`, resolve the subject in this order:

1. Existing public or private module.
2. Explicit path when the subject is path-like.
3. Known app or config locations for the target platform.
4. Cheap package, application, bundle, or desktop metadata.
5. A clarification question.

Adoption proposals should decide public versus private placement conservatively. Secrets, credentials, license files,
host-specific values, private endpoints, account identifiers, and uncertain private material belong in `home-` or
require clarification. Public-safe configuration may go in `home`.

Adoption must also propose `links` versus `copies`. Use `links` for stable user-owned config. Use `copies` for files or
directories that target applications are expected to overwrite.

Before writing an adoption, inspect dirty state in the target repository and in `home-` when it will be touched. Do not
overwrite uncommitted work without explicit confirmation.

### Home Workflow State

Home-management proposals are not deployment state. Do not write adoption, cleanup, organization, or diagnostic
proposals to `~/.local/state/tilde/hosts/HOST/state.md`.

For broad, risky, multi-file, multi-session, or interrupted home workflows, use `.agents/state/tasks/` as local task
state when useful. Keep durable decisions in this spec or in reviewed notes, not in deployment state.

### Apply Vocabulary

Follow-up phrases such as `apply`, `apply proposal`, `do it`, or `adopt it` refer to the latest proposal only when the
reference is unambiguous. If there is any ambiguity, summarize the proposal again before asking for confirmation.

With an active unambiguous proposal, `apply` applies that proposal after confirmation. Without an active proposal,
suggest `deploy dry-run`, `deploy`, or `update` as appropriate. Use `internal.apply` only for Tilde development or when
the user explicitly asks for internal command behavior.

If an action partially fails, report what changed, what did not change, and what remains. Do not promise automatic
rollback unless a rollback plan was explicitly prepared.

Remote destructive or preference-sensitive commands require confirmation that names the remote host, target home path,
and action set.

## Deployment

Deployment is the user-facing operation that prepares a host and installs Tilde desired state from configured public and
private data repositories. It may include initialization, bootstrap/preflight, repository preparation, provisioning plan
generation, provisioning apply, and deployment state update.

Deployment must not assume a fixed data repository location. Links and copies resolve from the public/private repository
copies that are actually being applied. Deployment may run locally or over SSH. Commands that deploy, initialize,
inspect, diagnose, or update a remote host may accept a Git-like target syntax:

```text
$tilde deploy ssh:<host>
$tilde deploy ssh:<host> ~/Dropbox/src/home
$tilde deploy ssh:<host> --public ~/src/home --private ~/src/home-
$tilde init ssh:<host> --public ~/src/home
$tilde update ssh:<host>
$tilde doctor ssh:<host>
$tilde status ssh:<host>
```

`ssh:<host>` identifies the target host. Public/private repository arguments identify the controller-side data
repositories by default. A future qualified syntax may distinguish controller-side sources from remote-side repository
paths if needed.

If no public/private arguments are given, Tilde resolves them from local state, router metadata, or the remote target's
configured state according to the command's semantics.

If the target machine already has a Dropbox-backed public data repository copy, use that copy. If the public repository
is cloned to a target machine, the default location is `~/.local/src/<repo-name>`. The directory name is the
repository's own name; do not force it to `home`.

### User Scenarios

When the Tilde skill is installed but no home repositories exist yet, the primary low-friction path is:

```text
$tilde create ~/Dropbox/src/home
$tilde adopt zsh
$tilde adopt git
$tilde deploy dry-run
$tilde deploy
```

`deploy` may also guide this scenario in one journey:

```text
$tilde deploy ~/Dropbox/src/home
```

If the public path does not exist, `deploy` may propose a `create` phase. A newly created empty repository should not
force immediate provisioning. Offer clear choices such as finishing initialization, running bootstrap checks, starting
adoption, or applying an empty/minimal desired state.

When public/private home repositories already exist, the typical local flow is:

```text
$tilde deploy ~/Dropbox/src/home
```

The equivalent explicit flow is:

```text
$tilde init ~/Dropbox/src/home
$tilde deploy
```

This flow identifies public/private repositories, validates repository roles, writes local Tilde state after
confirmation, writes or updates the home router after confirmation, runs bootstrap/preflight when needed, generates a
provisioning plan, and applies only after explicit confirmation.

### Host Kinds

Choose the host kind by asking whether the target repository copy is Dropbox-backed. A personal physical machine has no
special provisioning semantics by itself; it only changes the likelihood that Dropbox is available.

| Kind | When | Bootstrap | Repository copy | Deployment state handling | Default flow |
| --- | --- | --- | --- | --- | --- |
| `dropbox` | Target has a synced Dropbox copy of the public data repository. This is typical for personal physical machines when Dropbox quota and device limits allow it. | Run the installed skill bootstrap or the bootstrap helper available in the target context. | Use the target's Dropbox-backed public/private checkouts. | Target state under `~/.local/state/tilde` is authoritative; Dropbox may sync repository files, not runtime state. | local install or `remote-dropbox` |
| `git` | Target does not use Dropbox for the public data repository. This covers VPS hosts and personal machines where Dropbox is unavailable or undesired. | Deliver bootstrap before cloning, usually over SSH or the public bootstrap URL when available. | Clone or fetch into `~/.local/src/<repo-name>`. | Write state on the target, then optionally mirror it under the controller's `~/.local/state/tilde/remotes/HOST/`. | `remote-git` or local git-backed install |
| `self` | A user clones the public data repository or a fork and applies it on the same machine. | Prefer the public bootstrap URL when available; otherwise use the installed skill bootstrap after cloning. | User-chosen checkout, usually `~/.local/src/<repo-name>`. | Local deployment state stays under `~/.local/state/tilde`. Private `home-` behavior is optional. | local install |
| `any` | The target has an existing repository path whose branch, `HEAD`, or dirty state is intentionally accepted. | Use the installed skill bootstrap unless the target lacks the skill, then deliver bootstrap first. | Use the provided path as-is. | Write state on the target and mirror it only when requested or useful for orchestration. | `remote-any` |

Dropbox mode is valid only when the target machine's repository copy syncs through Dropbox. If a personal physical
machine cannot or should not use Dropbox, treat it as `git`.

### Dropbox Preflight

Dropbox installation and account linking are interactive preconditions. Tilde must not treat Dropbox installation as an
unattended provisioning action.

When the chosen host kind is `dropbox`, the agent first checks the target context for a Dropbox-backed checkout of the
public data repository. For remote SSH orchestration, inspect the target machine, not the local machine. If the checkout
is missing, unreadable, or clearly not synced, stop before normal install and guide the user through the
platform-appropriate manual Dropbox setup:

- macOS: install the Dropbox app, sign in, select or sync the repository, and wait until the checkout is present.
- Linux desktop: install the Dropbox package or daemon, sign in through the interactive flow, select or sync the
  repository, and wait until the checkout is present.
- Headless Linux or VPS: guide the user through Dropbox's headless Linux setup and account-link flow, then wait until
  the repository checkout is present. If headless Dropbox setup is not practical or the user declines it, switch to
  `git` host kind only after explicit confirmation.

After the user confirms Dropbox is installed, linked, and synced, re-run the preflight. Only then run bootstrap when
needed and continue to plan/install.

Do not create a separate Git clone on a target that was selected as `dropbox` unless the user explicitly changes the
host kind to `git`. This avoids two competing public data checkouts on personal machines.

### Bootstrap

The bootstrap helper is `bin/bootstrap` in the installed skill. It prepares the smallest baseline needed for normal
provisioning: transport tools, Homebrew, Ruby, `curl`, and `git`. Bootstrap must be Bash, must not require Ruby, must be
idempotent, and must remain outside normal module state.

Bootstrap has two separate concerns:

- **Delivery**: get the bootstrap script onto the target when the installed skill is not there yet.
- **Preparation**: run the bootstrap script so the target can clone or operate repositories and run the planner.

When the installed skill is already present on the target, run bootstrap from the installed skill:

```bash
bin/bootstrap
```

When bootstrapping a remote target that does not have the installed skill yet, deliver the script over SSH:

```bash
ssh HOST 'bash -s' < bin/bootstrap
```

When `tilde.roktas.dev` exists as the GitHub-backed public site for the installed skill, prefer the public bootstrap endpoint
where HTTPS and `curl` are available:

```bash
curl -fsSL https://tilde.roktas.dev/bootstrap | bash
```

This public transport is the default for `self` installs and a good default for `git` targets when the target can reach
the site. SSH delivery remains the fallback for private in-flight changes, targets without `curl`, locked-down networks,
or orchestrated installs that should use the local installed skill's exact bootstrap script.

A public or fork-based install may also fetch the same script from official release or raw Git metadata, but that
transport must be documented separately and should prefer immutable or trusted references when possible.

On apt-based Linux, bootstrap installs the small base needed for Homebrew, such as `build-essential`, `ca-certificates`,
`curl`, `file`, `git`, and `procps`, then installs Homebrew and installs `curl`, `git`, and `ruby` through Homebrew.

On macOS, bootstrap checks for Xcode Command Line Tools first, installs Homebrew, and installs `curl`, `git`, and
`ruby` through Homebrew. If Command Line Tools installation is started, bootstrap stops and the user reruns it after the
platform installer finishes.

### Remote Modes

- `remote-git`: deterministic default for SSH provisioning when the target does not have a Dropbox-backed public data
  checkout. Prepare the target public repository by cloning or fetching it, usually under `~/.local/src/<repo-name>`.
  Use `main` and the latest pushed commit unless instructed otherwise. Require a clean local worktree and a pushed
  commit.
- `remote-dropbox`: use the target public repository that already exists under Dropbox. Local and target Git `HEAD` do
  not need to match. Runtime state stays under `~/.local/state/tilde` on the target.
- `remote-any`: use the provided target repository path as-is. This is intentionally less deterministic; call out
  branch, `HEAD`, and dirty-state uncertainty and continue only with explicit confirmation.

In all remote modes, resolve links, copies, and home inspections against the target machine's home directory and target
repository copies, not the local orchestrating repository. Write deployment state on the target first. The controller may
copy or summarize the target state into its read-only remote mirror before finishing.

## Provisioning

Provisioning is the lower-level module operation performed during deployment. It is intended to be idempotent where
practical, but it is not perfectly idempotent.

### Modes

- `apply`: apply repository desired state to the target host. This covers first provisioning and normal state/`HEAD`
  reconciliation, including new links, copies, packages, and selected special sections.
- `refresh`: update only managed external resources: active plan packages and `README.md` `Update` sections. It may run
  even when `HEAD` is unchanged.
- `repair`: retry modules marked `notok` in deployment state at the same `HEAD`.
- `upgrade`: broad package-manager upgrade mode. It may affect packages outside the managed set and runs only on
  explicit user request after scope is described.

`apply` and `repair` are deployment-state/`HEAD` driven. `refresh` and `upgrade` are external-resource/time driven.
The user-facing `update` command runs the `apply` and `refresh` phases in that order, after confirmation, so new desired
state and existing managed external resources can both be brought current.

### Init

- Read current deployment state. Missing deployment state means a fresh install.
- Compare repository `HEAD` with deployment state `head`.
- Identify changes that require provisioning. Frontmatter changes usually matter; changes to already-linked module files
  usually do not require relinking.
- Process changed or required modules.

### Traverse

- Plan core managed links first.
- Process the active platform module first.
- Process the active platform variant second, when present.
- Process active other root modules alphabetically.
- Enter each module directory, read `README.md`, load frontmatter, and merge `all` with the active platform scope.
- Interpret `HEAD`/deployment-state differences to produce the active provisioning set. Added packages, added links,
  removed links, and added copies matter. Removed packages and removed copies are not automatic removal actions.
- In `apply`, run install and link phases.
- In `refresh`, refresh packages and selected `Update` sections in managed scope only.
- In `repair`, retry `notok` modules at the same `HEAD`.
- In `upgrade`, run broad package-manager updates only after explicit confirmation.
- Save deployment state.

### Ordering

- The active platform module runs first.
- The active platform variant runs immediately after the platform module.
- Other root modules run alphabetically by directory name. `misc` has no special position.
- A future `order` frontmatter key may be interpreted as numeric weight. Modules without `order` use the default weight;
  ties keep alphabetical order.

### Install

- Run `Preinstall` instructions when present.
- Install added packages from the active provisioning set, grouped by package type. Do not remove packages removed from
  frontmatter.
- Run `Install` and `Postinstall` instructions when present.

### Link

- Run `Prelink` or `Presetup` instructions when present.
- Create added symlinks.
- Create added copies.
- Remove a dropped link only if the target is a symlink into the active data repository or a dangling symlink. Do not
  touch dropped link targets that are not symlinks or point outside the active data repository.
- Do not automatically remove dropped copy targets.
- Run `Link`, `Postlink`, or `Setup` instructions when present.

### Update

- Run `Update` instructions only in `refresh` or explicitly requested `upgrade`. Do not run them during normal `apply`.

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
- `flatpak:<app-id>`: `flatpak install --user flathub <app-id>` unless the module explicitly requires system-wide
  Flatpak install.
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
- `flatpak:<app-id>`: `flatpak update --user <app-id>` for per-user installs created by Tilde.
- `scoop:<name>`: run `scoop update` first, then `scoop update <name>`.
- `github:<owner>/<repo>`: inspect latest release assets again, compare with the installed binary when possible, and
  replace the executable only after selecting the matching asset.
- `skill:<source>`: fetch the matching Git checkout and update with a non-destructive fast-forward-only merge. Dirty
  targets block automatic updates. Put any nonstandard Tilde skill update behavior in the owning module's `README.md`
  body instead of expanding `skill:` into a broad skill-management schema.
