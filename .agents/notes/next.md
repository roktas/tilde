# Tilde Next Draft Spec

This note is a non-canonical draft for the next Tilde design. Promote stable decisions into the canonical spec after
review.

## Goals

- Split Tilde into a control plane and data planes.
- Keep Tilde installable as a normal agent skill.
- Let other users bring their own public and private home repositories while following the Tilde protocol.
- Keep first-run workflows convenient without hiding writes, repository creation, host preparation, or provisioning.
- Keep the user-facing command surface small; use internal semantic commands for lower-level behavior.

## Repository Roles

Tilde has three conceptual layers:

- Control plane: the installed `tilde` skill, normally at `~/.agents/skills/tilde`.
- Public data plane: the user's public home repository, conventionally named `home`.
- Private data plane: the user's private companion repository, conventionally named `home-`.

The protocol must not rely on repository names for correctness. `home` and `home-` are conventions only. Repository
identity should be declared in existing repository-facing files, preferably `AGENTS.md` YAML frontmatter, rather than a
new root manifest file.

Example public repository identity:

```markdown
---
tilde:
  protocol: tilde/v1
  role: public
  private: ../home-
---

# Agent Instructions

This repository is the public data layer for a Tilde-managed home.
Use the installed `tilde` skill for deployment, planning, adoption, and managed-link work.
```

Example private repository identity:

```markdown
---
tilde:
  protocol: tilde/v1
  role: private
  public: ../home
---

# Agent Instructions

This repository is the private companion data layer for a Tilde-managed home.
Read this file before preference-sensitive home commands.
```

`README.md` remains the human-facing repository overview. It may explain Tilde usage, but agent/runtime identity should
prefer `AGENTS.md`.

## Installed Skill

The control plane should be treated as an ordinary skill installation, not as a special engine checkout.

Canonical control-plane location:

```text
~/.agents/skills/tilde
```

The installed skill owns:

- prompt command semantics;
- durable protocol references;
- helper commands such as planning and bootstrap helpers;
- router templates or generation logic;
- validation and diagnostics logic.

The installed skill must not be the canonical storage location for user-specific home data or host runtime state.

## Skill Installation and Updates

Tilde itself is installed and updated as a skill. External package-manager distribution is out of scope for this draft.

There are three lifecycle modes:

- Bootstrap: an external path installs enough agent runtime and Tilde skill to run `$tilde create`, `$tilde init`, or
  `$tilde deploy`.
- Managed steady state: the user's public/private home configuration keeps the installed Tilde skill current.
- Development/local-current: Tilde is already present on the machine, usually from a local checkout, and must not be
  reinstalled, downgraded, or self-updated unless the user explicitly asks for it.

Managing the Tilde skill must not create a bootstrapping loop. Deployment may require the skill to exist before public
and private data repositories have been installed.

The preferred managed form is a normal package entry in a dedicated `tilde` module:

```yaml
---
packages:
  - skill:github.com/roktas/tilde
---
```

`skill:<source>` installs or updates an agent skill from a Git-backed source. It is a package type, not a separate skill
management subsystem.

Scalar `skill:` rules:

- accepted sources include `github.com/<owner>/<repo>` and full Git URLs;
- the source repository contains the skill at its root;
- the skill name is the source repository basename;
- the target is `~/.agents/skills/<name>`;
- install clones the source when the target is missing;
- update is non-destructive by default, such as fetch plus fast-forward-only merge;
- dirty targets block automatic updates;
- an existing non-Git target or mismatched checkout is a proposal-time conflict.

Local development can use ordinary links instead:

```yaml
---
links:
  ../tilde: ~/.agents/skills/tilde
---
```

Do not grow `skill:` into a broad skill-management schema. If a user needs different behavior for the Tilde skill, put
those instructions in the `tilde` module's `README.md` body and let the normal module special-instruction mechanism
handle it.

## Local State

Machine-specific runtime state should live outside the skill and outside the public/private data repositories by
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
    <host>/
      state.md
      last-plan.json
      last-apply.json
  remotes/
    <host>/
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

Host state should record enough provenance to explain what was applied:

```yaml
host: example-host
skill_version: ...
public_commit: ...
private_commit: ...
applied_at: ...
```

Repository-local `.agents/state/` remains appropriate for local task state, checkpoints, logs, and development
scratch. It should not become the canonical deployment state for a user's host unless a specific compatibility mode
requires it.

For remote deployments, the target host's state under its own `~/.local/state/tilde` is authoritative. The controller
machine may keep a read-only mirror for status and history, for example under
`~/.local/state/tilde/remotes/<host>/`, but remote state is not owned by the public/private data repositories.

## Discovery

Discovery should be bounded. Tilde must not recursively scan `$HOME` to find repositories.

Resolution order:

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

With one positional argument, the argument is the public repository. The private repository may be discovered from
frontmatter or a sibling path such as `home-`.

With two positional arguments, the first is public and the second is private.

Default repository locations are convenience only. If no explicit public path is given, Tilde may propose:

1. `~/Dropbox/src/home` and `~/Dropbox/src/home-` when `~/Dropbox/src` exists.
2. `~/.local/src/home` and `~/.local/src/home-` otherwise.

If a default path already exists, Tilde should inspect it for Tilde repository identity before using it. If it does not
exist, `create` or `deploy` may offer to create it after confirmation.

## Home Router

`~/AGENTS.md` should route agents from the user's home directory to the installed Tilde skill and the configured data
repositories.

After the control/data split, router generation is the normal model. Local initialization writes or updates this short
host-local router after confirmation. The old direct symlink to a static router file remains a compatibility behavior
for the combined repository model.

Example router identity:

```markdown
---
tilde:
  protocol: tilde/v1
  skill: ~/.agents/skills/tilde
  public: ~/Dropbox/src/home
  private: ~/Dropbox/src/home-
---

# Home Agent Router

Use the installed Tilde skill for Tilde home-management commands.
```

The router should stay short. Personal policy belongs in the private repository's `AGENTS.md`, not in the home router.

## User Scenarios

### Tilde Skill Installed, No Home Repositories Yet

This user already has an agent runtime and the installed Tilde skill, but has not created public/private data
repositories.

Primary flow:

```text
$tilde create ~/Dropbox/src/home
$tilde adopt zsh
$tilde adopt git
$tilde plan
$tilde deploy
```

Guided flow:

```text
$tilde deploy ~/Dropbox/src/home
```

If the public path does not exist, `deploy` may propose a `create` phase. A newly created empty repository should not
force immediate provisioning. The user should be offered clear choices, such as finishing initialization, running
bootstrap checks, starting adoption, or applying an empty/minimal desired state.

### Existing Public and Private Repositories

This user already has `home` and optionally `home-`. This scenario should preserve the existing local/remote,
Dropbox/Git, and fresh-host deployment behavior.

Typical local flow:

```text
$tilde deploy ~/Dropbox/src/home
```

Equivalent explicit flow:

```text
$tilde init ~/Dropbox/src/home
$tilde deploy
```

The command should:

- identify public and private repositories;
- validate repository roles;
- write or update local Tilde state after confirmation;
- write or update the home router after confirmation;
- run bootstrap/preflight behavior when needed;
- generate a provisioning plan;
- apply only after explicit confirmation.

Dropbox targets must preserve Dropbox preflight semantics. Git or remote targets must preserve clean-worktree and pushed
commit requirements where applicable.

### Remote Deployment Targets

Commands that deploy, initialize, inspect, diagnose, or update a remote host may accept a Git-like target syntax:

```text
$tilde deploy ssh:<host>
$tilde deploy ssh:<host> ~/Dropbox/src/home
$tilde deploy ssh:<host> --public ~/src/home --private ~/src/home-
$tilde init ssh:<host> --public ~/src/home
$tilde update ssh:<host>
$tilde doctor ssh:<host>
$tilde status ssh:<host>
$tilde links ssh:<host>
```

`ssh:<host>` identifies the target host. Public/private repository arguments identify the controller-side data
repositories by default. A future qualified syntax may distinguish controller-side sources from remote-side repository
paths if needed.

If no public/private arguments are given, Tilde resolves them from local state, router metadata, or the remote target's
configured state according to the command's semantics.

Remote actions must name the target host, target home path when known, repository source, and expected blast radius
before making changes. Remote deployment writes authoritative runtime state on the target host and may copy or summarize
that state back to the controller's read-only remote mirror.

## Command Model

Public commands should describe user journeys and intentional user actions. Lower-level semantic commands should exist
for the skill and spec, but should not clutter ordinary user help.

### Public Commands

- `help`: show public command help.
- `create`: create public/private home repository skeletons.
- `init`: register existing public/private repositories on this host.
- `deploy`: prepare this host and install desired state.
- `plan`: show the install plan without applying it.
- `update`: reconcile desired state and refresh managed external resources.
- `repair`: retry failed install phases from recorded state.
- `status`: show a short deployment and router summary.
- `doctor`: run bounded diagnostics.
- `links`: inspect managed links and copies.
- `adopt`: adopt an app, config, package, or path into public or private data.
- `upgrade`: run broad package-manager upgrades after explicit confirmation.
- `clean`: propose conservative cleanup for selected home content.
- `organize`: propose organization changes for selected home content.
- `archive`: archive selected content according to private policy.
- `dedupe`: find and propose handling for duplicate selected home content.

### Internal Semantic Commands

Commands in the `internal.` namespace are internal semantic commands. They are not shown by ordinary `$tilde help`, are
not intended as user-facing entrypoints, and may be used by the skill/spec to define higher-level behavior.

For convenience while writing prompt-level specs or during Tilde development, `.name` may be accepted as shorthand for
`internal.name`. The dotted form is intended to signal private/internal semantics and leaves room for future namespaces.

Possible internal commands:

- `internal.bootstrap` or `.bootstrap`: run or plan the fresh-host bootstrap prelude.
- `internal.plan` or `.plan`: generate a provisioning plan.
- `internal.apply` or `.apply`: apply a provisioning plan.
- `internal.install` or `.install`: install desired state from public/private data repositories.
- `internal.refresh` or `.refresh`: refresh managed external resources.
- `internal.repair` or `.repair`: retry failed modules or failed installation phases from recorded state.

If a user explicitly requests an internal command, the agent should explain that it is internal and suggest the public
command that covers the same workflow, unless the user is developing Tilde itself.

CLI implementations should treat dotted command tokens as command names before path or extension interpretation, or
otherwise provide an unambiguous way to invoke internal commands during development.

### Command Relationships

Suggested relationships:

```text
deploy = init + internal.bootstrap/preflight + internal.install
update = internal.install + internal.refresh
plan   = public view over internal.plan
repair = public wrapper over internal.repair
```

`create` creates or proposes repository skeletons. It should not deploy by itself.

`init` binds existing repositories to the current host. It should not provision by itself.

`deploy` is the main first-run and new-host journey command. It may orchestrate repository creation, initialization,
bootstrap/preflight, planning, and installation, but it must preserve each phase's proposal-first behavior.

## Proposal-First Rules

Repository creation, repository edits, router writes, state writes, package changes, file links, file copies, remote-host
actions, and destructive home-management actions must be proposal-first.

Proposals should name:

- target paths or hosts;
- what will be written, moved, removed, linked, copied, or installed;
- whether public or private data will be touched;
- whether runtime state will be updated;
- the expected blast radius.

## Compatibility Notes

The current combined repository model should be supported during migration. A compatibility mode may treat the current
Tilde checkout as both control plane and public data plane until the split is complete.

The durable migration path should be:

1. Add data repository identity semantics.
2. Add local state and router semantics for public/private bindings.
3. Add `create`, `init`, and revised `deploy` semantics.
4. Introduce `internal.` command semantics and `.` shorthand.
5. Preserve existing Dropbox/Git/local/remote deployment behavior.
6. Add Tilde skill installation/update policy without creating a bootstrapping loop.
7. Split the current repository into installed skill/control and public/private data repositories.

## Local Migration Notes

These notes are for the maintainer's own deployment during the migration. Do not promote them into the public spec.

- Do not create a separate `tilde` module for the maintainer's own home repository.
- Keep the Tilde skill managed from the existing `agents` module with a local symlink under `agents/skills`:

```text
home/agents/skills/tilde -> ../../../tilde
```
