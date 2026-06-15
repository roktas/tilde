# Tilde

Tilde is an agent skill and control plane for reconciling a host with desired state stored in public and private home
repositories.

The canonical contract is [references/specification.md](references/specification.md). That specification defines the
stateless provisioning model used by the skill and runtime helpers.

## Install

Install this repository as the Tilde skill:

```text
~/.agents/skills/tilde
```

Local development may point the installed skill path directly at this checkout:

```text
~/.agents/skills/tilde -> ~/Dropbox/tilde
```

Managed user installs may use the Tilde package declaration:

```yaml
---
all:
  packages:
    - skill:github.com/roktas/tilde
---
```

## Model

Tilde derives desired state from the current committed public/private home repositories and targeted live checks.
Runtime state must not become desired state.

Persistent state is intentionally compact:

```text
~/.local/state/tilde/state.yml
```

`state.yml` stores repository bindings and the last fully converged commit anchors. Planning evaluates current manifests
and targeted live facts on every run.

If `state.yml` is missing, Tilde treats the host as fresh, applies current desired state idempotently, and skips
commit-diff cleanup because there is no old anchor.

## Data Repositories

Public and private home data repositories declare their role in `AGENTS.md` frontmatter:

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

Repository names are conventions only. Correctness comes from explicit paths, state bindings, and repository identity.

## Modules

Each root module is a direct child directory containing `README.md`. README frontmatter may declare `links`, `copies`,
`packages`, `level`, `hosts`, and platform scopes such as `all`, `linux`, and `macos`.

Recommended module sections:

```text
## Prerequisites
## Install
## Post Install
## Configure
## Update
## Notes
```

Code blocks must be idempotent or guarded. If an effect cannot be safely detected from live target facts, represent it as
a prerequisite, note, or explicit proposal-first operator action.

## Commands

Tilde prompt markers such as `/tilde` and `$tilde` are prompt contracts, not shell commands. Use `/tilde` in examples to
avoid confusing prompt notation with shell variable expansion. The installed runtime router also provides implemented
helper routes through `bin/tilde`. Some commands are interpreted by the agent; some are direct runtime routes.

When a shell runtime helper is needed, resolve the runtime entrypoint from the loaded skill directory's `bin/tilde`.
Fallback to the installed skill path:

```sh
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
```

Do not rely on bare `tilde` being on the controller `PATH`.

| Command | Kind | Action |
| --- | --- | --- |
| `help` | runtime | Show public commands or one command's usage. |
| `deploy` | agent | Prepare a local or remote host and apply desired state. |
| `update` | agent | Run explicit update behavior from the current desired state. |
| `repair` | agent | Apply current desired state again. |
| `doctor` | runtime | Diagnose without executing module code or mutating targets. |
| `handoff` | runtime | Copy and print the privilege handoff command for the local or remote host. |
| `align` | dual | Reconcile links and copies without bootstrap, packages, or module code. |
| `adopt` | agent | Propose adopting an app, config, package, or path. |
| `create` | agent | Propose public/private home repository creation. |
| `init` | agent | Bind existing public/private repositories. |
| `clean` | agent | Propose conservative cleanup. |
| `organize` | agent | Propose organization changes. |
| `upgrade` | agent | Run the widest explicitly requested update path. |

Kind meanings:

- `agent`: interpreted by the loaded Tilde skill; no direct runtime route.
- `runtime`: direct `bin/tilde` route. For remote targets, run it on the target through `"$TILDE" ssh HOST`.
- `dual`: direct local runtime route plus prompt workflow. Remote targets are agent-orchestrated.

For agent workflows, `update` maps to planning mode `refresh`. Plans for remote hosts must be generated and applied on
the target host. After a successful mutating remote apply, read final status on the target before closeout.

For host-aware prompt commands, omitted target means current host, bare `HOST` means `ssh:HOST`, and `ALL` means every
managed host defined by the active home policy. For remote workflows, target state is also read on the target host. Do
not use the controller's
`~/.local/state/tilde/state.yml` to discover remote repository bindings, applied anchors, level, platform, or bootstrap
state.

Example prompts:

```text
/tilde deploy
/tilde deploy HOST
/tilde update
/tilde update HOST
/tilde update ALL
/tilde repair
/tilde doctor
/tilde align
```

Use `dry-run` or `plan-only` when the user wants the proposal without applying it.

## Helpers

Module code blocks run with Tilde's `bin/` directory at the front of `PATH`. The small file-patching helpers are:

```text
line ensure FILE LINE
line remove FILE LINE
span ensure FILE ID
span remove FILE ID
```

Use the same plain helper names for privileged targets, for example `sudo line ...`.

Helpers emit one JSON object per stdout line using the `tilde.helper/v1` schema. Human-readable diagnostics go to
stderr.

## Safety

Tilde is proposal-first for destructive, privilege-requiring, preference-sensitive, or remote mutations.

No proof means no destructive mutation. Managedness must be proven before removing links, spans, copies, files, or
packages.

Package manager state is the source of truth for package presence. Package inventories are ephemeral apply-time
optimizations only.

One-off operator workflows stay outside the desired-state model. Tilde may assist with checks and execution.

## References

- [Specification](references/specification.md)
- [Repository Development](references/development.md)
