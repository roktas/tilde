# Tilde

Tilde is an agent skill and control plane for home provisioning and workspace management.

It operates on separate public and private home data repositories. The control plane lives here; user-specific desired
state and policy live in the data repositories.

## Install

Install this repository as:

```text
~/.agents/skills/tilde
```

Local development may install it through an ordinary symlink from a home data module, for example:

```text
home/agents/skills/tilde -> ../../../tilde
```

Managed user installs may use the Tilde package declaration:

```yaml
---
all:
  packages:
    - skill:github.com/roktas/tilde
---
```

## Quick Start

### New Data Repositories

For a new user who has the Tilde skill installed but no home data repositories yet:

```text
$tilde create
$tilde adopt zsh
$tilde adopt git
$tilde deploy dry-run
$tilde deploy
```

With no path, Tilde proposes the conventional public/private pair under `~/Dropbox` when available, and otherwise uses
`~/.local/src`.

### Existing Data Repositories

For an existing public/private home repository pair:

```text
$tilde init
$tilde deploy
$tilde update
```

Use explicit paths when the repositories do not follow the default convention:

```text
$tilde init PUBLIC_REPO PRIVATE_REPO
```

### Update An Existing Deployment

After a host has already been deployed, reconcile changed desired state and run the fast update path:

```text
$tilde update
```

For a remote host:

```text
$tilde update ssh:<host>
```

Use `dry-run` or `plan-only` first when you want the proposal without applying it:

```text
$tilde update dry-run
$tilde update ssh:<host> dry-run
```

Use `update full` for the full managed update path, including managed non-system package declarations and module
`Update` sections:

```text
$tilde update full
```

Use `upgrade` for the widest update path. It includes `update full`, then runs broad package-manager upgrades that may
affect packages not declared by Tilde:

```text
$tilde upgrade
```

### Adopt New State After Deployment

When you start using a new app or want Tilde to manage an existing config or path, adopt it into the data repositories,
then update the deployed host:

```text
$tilde adopt APP_OR_PATH
$tilde update dry-run
$tilde update
```

To apply the same accepted desired-state change to an already deployed remote host:

```text
$tilde adopt APP_OR_PATH
$tilde update ssh:<host> dry-run
$tilde update ssh:<host>
```

`adopt` inspects the requested subject and proposes public/private data-repository placement before writing. The update
step applies the accepted desired-state change to the target host.

### Remote Host

For a remote host:

```text
$tilde deploy ssh:<host>
$tilde status ssh:<host>
$tilde doctor ssh:<host>
```

### Remote Git VPS

For a minimal VPS or other remote host without Dropbox, deploy over Git with only the public data repository:

```text
$tilde deploy ssh:<host> --public PUBLIC_REPO
```

Add the private data repository when private modules or policy should be installed on that host:

```text
$tilde deploy ssh:<host> --public PUBLIC_REPO --private PRIVATE_REPO
```

Tilde clones or fetches the selected repositories on the target, normally under `~/.local/src/<repo-name>`, then writes
runtime state on the target under `~/.local/state/tilde`.

### Remote Dropbox Host

For a new Dropbox-backed machine reachable over SSH, first install and link Dropbox on the target and wait until the
public/private data repositories are synced there. If local or target Tilde state already identifies the repositories,
or they follow the default convention, run:

```text
$tilde deploy ssh:<host>
```

Use explicit controller-side repository paths when discovery is ambiguous:

```text
$tilde deploy ssh:<host> --public PUBLIC_REPO --private PRIVATE_REPO
```

During `remote-dropbox`, Tilde must use the target machine's Dropbox-synced public/private checkouts for planning and
installation, not clone a second checkout and not treat controller-side paths as remote paths. If no private data
repository is configured, omit `--private PRIVATE_REPO`.

Bare `$tilde` means `help`.

## Data Repositories

Public and private home data repositories declare their Tilde role in `AGENTS.md` frontmatter:

```yaml
---
tilde:
  protocol: tilde/v1
  role: public
  private: ../PRIVATE_REPO
---
```

```yaml
---
tilde:
  protocol: tilde/v1
  role: private
  public: ../PUBLIC_REPO
---
```

Repository directory names are conventions. Tilde uses explicit command arguments, local state, home-entrypoint
metadata, and repository identity frontmatter to find the active public/private repositories.

### Customization

Home customization belongs in `~/AGENTS.md`, whose scope is the user's home directory. In steady state, Tilde manages
that file from a version-tracked data repository source:

- the private data repository's `home/AGENTS.md` when a private data repository is configured;
- the public data repository's `home/AGENTS.md` as the fallback when no private data repository is configured.

The public/private repository root `AGENTS.md` files are for repository identity and repository-scope agent
instructions, not target-home layout policy.

Data-layer customization uses ordinary Markdown sections in existing files. Tilde treats these sections as user policy
and instructions, not as control-plane specification.

Valid locations are:

- the home entrypoint source, meaning `home/AGENTS.md` inside the selected data repository;
- host `hosts/HOST/README.md` files for host-specific policy;
- module `README.md` files for module-local policy.

Use `## Layout` for home or workspace layout facts used by bounded discovery and preference-sensitive commands. Use
free text under the section, plus optional third-level headings for specific `~`-relative paths.

Use `## Operations` for command-specific policy. Third-level headings are public command names such as `### adopt`,
`### clean`, or `### deploy`, or custom command names such as `### custom.sync-host`.

Data repositories must not define or override `internal.*` commands. Customization also cannot weaken safety rules such
as proposal-first writes, bounded discovery, explicit destructive confirmation, or hiding internal commands from
ordinary help.

Custom commands such as `custom.sync-host` are invoked by exact command name, for example
`$tilde custom.sync-host`. They are not listed in ordinary `$tilde help`; `$tilde help custom.sync-host` shows the
resolved data-repository instructions when that custom command exists.

```markdown
## Layout

Use runtime XDG user dirs for localized desktop directories.

### `~/Dropbox`

Source checkouts live directly under `~/Dropbox`.

## Operations

### adopt

Private material goes to the private data repository by default.

### custom.sync-host

Synchronize the matching host directory in the private data repository with `~/.<host>` on the remote machine. Never
delete remote files by default.
```

Tilde applies data-layer instructions from broad to narrow:

```text
control-plane spec
< public home entrypoint source home/AGENTS.md
< private home entrypoint source home/AGENTS.md
< host hosts/HOST/README.md
< module README.md
< explicit user request
```

The `home` module owns the home-directory entrypoint. Its `README.md` normally links `AGENTS.md` into `~/AGENTS.md`.
Tilde may generate a minimal fallback `~/AGENTS.md` during first-run or when no data-repository home entrypoint exists
yet; deploy should replace that fallback with the data-repository link once available.

### Modules

Each root module is a direct child directory of the active public or private data repository and is recognized only when
it contains `README.md`. Private companion repositories use the same module rules as public repositories and may contain
private modules and policy.

Module `README.md` files may use YAML frontmatter to declare:

- `links`: module files or directories to symlink into the target home;
- `copies`: module files or directories to copy into the target home;
- `packages`: packages, release assets, or skills to install;
- `level`: `minimal`, `normal`, or `extra` provisioning scope;
- `hosts`: short host names where the module applies;
- platform scopes: `all`, `linux`, `macos`, and `windows`.

README bodies are agent instructions. Conventional sections such as `Install`, `Preinstall`, and `Update` may contain
guarded commands; commands run only after confirmation. Use frontmatter for stable desired state, and use README body
instructions when behavior depends on runtime checks or local policy.

### Repository Locations and State

Tilde does not assume a fixed data repository location. `create`, `init`, `deploy`, `status`, and remote commands
resolve repositories from explicit `--public` and `--private` options, positional arguments, local Tilde state,
home-entrypoint metadata, and confirmed sibling repositories. `create`, `init`, and first-run `deploy` may also use
default locations after inspecting repository identity and presenting a proposal.

Default locations are convenience only:

```text
public/private repository paths under ~/Dropbox
public/private repository paths under ~/.local/src
```

Machine runtime state lives outside the skill and data repositories, under `~/.local/state/tilde` by default. For a
Dropbox-backed target, Tilde uses the target's synced repository copy and keeps runtime state on the target. For a
Git-backed target, Tilde clones or fetches the public repository, normally under `~/.local/src/<repo-name>`.

## Command Inventory

`$tilde help` shows public commands as a Markdown table. Internal semantic commands such as `internal.apply` are for
Tilde development and are not shown in ordinary help.

The installed helper `bin/help --format markdown` emits the same public table.

Bare `$tilde` means `help`.

Use `dry-run` or `plan-only` as a qualifier on commands such as `deploy` or `update` when you want the proposal without
applying it.

| Command | Action |
| --- | --- |
| `adopt` | Adopt an app, config, package, or path into the public or private data repository. |
| `clean` | Propose conservative cleanup, including duplicate candidates when relevant. |
| `create` | Create public/private home repository skeletons. |
| `deploy` | Prepare a host and install desired state. |
| `doctor` | Diagnose deployment, repository, host, home-entrypoint, and managed-link health. |
| `help` | Show public commands or detailed help for one public command. |
| `init` | Register existing public/private repositories on this host. |
| `organize` | Propose organization changes, including archive moves when relevant. |
| `repair` | Retry failed install phases from recorded state. |
| `status` | Show a short deployment, home-entrypoint, and managed-surface summary. |
| `update` | Reconcile desired state, then run the fast update path. |
| `upgrade` | Run `update full`, then broad package-manager upgrades after explicit confirmation. |

Example prompts shown by help:

```text
$tilde deploy
$tilde deploy ssh:<host>
$tilde deploy ssh:<host> --public PUBLIC_REPO
$tilde adopt APP_OR_PATH
$tilde update dry-run
```

`status` is intentionally fast and state-first. It reads local Tilde state, cached plan/apply summaries, configured
repository summaries, and home-entrypoint facts. If deployment state or caches are missing, it returns a partial summary and
suggests `$tilde status discover`, `$tilde doctor`, or `$tilde deploy` instead of silently doing a long discovery pass.

## References

See `references/specification.md` for the canonical specification entrypoint, always-read contract, and routing map.
Detailed behavior lives in the routed files under `references/specification/`.
