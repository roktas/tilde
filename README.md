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

For a new user who has the Tilde skill installed but no home data repositories yet:

```text
$tilde create PUBLIC_REPO
$tilde adopt zsh
$tilde adopt git
$tilde deploy dry-run
$tilde deploy
```

For an existing public/private home repository pair:

```text
$tilde init PUBLIC_REPO
$tilde deploy
$tilde update
```

For a remote host:

```text
$tilde deploy ssh:<host>
$tilde status ssh:<host>
$tilde doctor ssh:<host>
```

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

Data-layer customization uses a `## Tilde` section in existing Markdown files. Tilde treats this section as user policy
and instructions, not as control-plane specification.

Valid locations are:

- the home entrypoint source, meaning `home/AGENTS.md` inside the selected data repository;
- host `hosts/HOST/README.md` files for host-specific policy;
- module `README.md` files for module-local policy.

Inside `## Tilde`, use typed third-level headings:

- `### Command: NAME` for public commands such as `adopt`, `clean`, or `deploy`, or for custom commands such as
  `custom.sync-host`;
- `### Layout: PATH` for home or workspace layout facts used by bounded discovery and preference-sensitive commands.

Data repositories must not define or override `internal.*` commands. Customization also cannot weaken safety rules such
as proposal-first writes, bounded discovery, explicit destructive confirmation, or hiding internal commands from
ordinary help.

Custom commands such as `custom.sync-host` are invoked by exact command name, for example
`$tilde custom.sync-host`. They are not listed in ordinary `$tilde help`; `$tilde help custom.sync-host` shows the
resolved data-repository instructions when that custom command exists.

```markdown
## Tilde

### Command: adopt

Private material goes to the private data repository by default.

### Command: custom.sync-host

Synchronize the matching host directory in the private data repository with `~/.<host>` on the remote machine. Never
delete remote files by default.

### Layout: ~

Use runtime XDG user dirs for localized desktop directories.

### Layout: ~/Dropbox

Source checkouts live under `~/Dropbox/src`.
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
public/private repository paths under ~/Dropbox/src
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
| `update` | Reconcile desired state, then refresh managed external resources. |
| `upgrade` | Run broad package-manager upgrades after explicit confirmation. |

`status` is intentionally fast and state-first. It reads local Tilde state, cached plan/apply summaries, configured
repository summaries, and home-entrypoint facts. If deployment state or caches are missing, it returns a partial summary and
suggests `$tilde status discover`, `$tilde doctor`, or `$tilde deploy` instead of silently doing a long discovery pass.

## References

See `references/specification.md` for the canonical specification entrypoint, always-read contract, and routing map.
Detailed protocol, command, home, customization, deployment, provisioning, and package semantics live under
`references/specification/`.
