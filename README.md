# Tilde

Tilde is an agent skill and control plane for home provisioning and workspace management.

It operates on separate public and private home data repositories. The control plane lives here; user-specific desired
state and policy live in data repositories such as `home` and `home-`.

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
$tilde create ~/Dropbox/src/home
$tilde adopt zsh
$tilde adopt git
$tilde deploy dry-run
$tilde deploy
```

For an existing public/private home repository pair:

```text
$tilde init ~/Dropbox/src/home
$tilde deploy
$tilde update
```

For a remote host:

```text
$tilde deploy ssh:<host>
$tilde status ssh:<host>
$tilde doctor ssh:<host>
```

Bare `$tilde` means `update`.

## Data Repositories

Public and private home data repositories declare their Tilde role in `AGENTS.md` frontmatter:

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

Data-layer customization uses a `## Tilde` section in repository, host, or module Markdown files:

```markdown
## Tilde

### Command: adopt

Private material goes to `home-` by default.

### Layout: ~/Dropbox

Source checkouts live under `~/Dropbox/src`.
```

## Command Inventory

`$tilde help` shows only public commands. Internal semantic commands such as `internal.apply` are for Tilde development
and are not shown in ordinary help.

Bare `$tilde` means `update`.

Use `dry-run` or `plan-only` as a qualifier on commands such as `deploy` or `update` when you want the proposal without
applying it.

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

## References

See `references/spec.md` for the protocol, command inventory, and provisioning semantics.
