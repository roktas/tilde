# Tilde

Tilde is an agent skill and control plane for reconciling a host with desired state stored in public and private home
repositories. The canonical contract is [references/specification.md](references/specification.md). That specification
defines the stateless provisioning model used by the skill and runtime helpers.

- Tilde primarily targets Debian-based Linux distributions and macOS hosts.
- It can run on a single machine, but the main operating model is provisioning a machine farm over SSH.
- Tailscale is strongly recommended for that SSH fabric.
- Git is the primary transport and synchronization mechanism; Dropbox-backed hosts are also supported.
- After the base system bootstrap, most user tools are installed with Homebrew on both platforms.
- Linux desktop hosts additionally use Flatpak for desktop applications that are better managed outside Homebrew.
- The skill has been developed with Codex 5.5, but its workflow, guardrails, and deterministic helper routes are tuned
  for day-to-day use with DeepSeek Flash V4, especially the max variant.

For a concrete public data repository, see [github.com/roktas/home](https://github.com/roktas/home). It shows the
expected shape of a Tilde-managed home repository: root modules with `README.md` manifests, package declarations,
managed links and files, and platform-specific lifecycle sections.

> [!WARNING]
> Tilde is currently pre-alpha software. Deployment experience is used to continuously refine and train the skill, so
> make sure you are using the latest version before each deployment.

## Install

Install this repository as the Tilde skill:

```text
~/.agents/skills/tilde
```

Local development may point the installed skill path directly at this checkout:

```text
~/.agents/skills/tilde -> ~/Dropbox/tilde
```

On Dropbox-backed interactive hosts, that symlink is also the steady-state runtime shape. A Git checkout cloned directly
under `~/.agents/skills/tilde` is only a provisional bootstrap or freshness runtime until `~/Dropbox/tilde` is present,
clean, executable, and current.

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

If `state.yml` is missing, Tilde uses fresh-run semantics, applies current desired state idempotently, and skips
commit-diff cleanup because there is no old anchor. Missing state alone does not prove that the host was never deployed.

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

Each root module is a direct child directory containing `README.md`. README frontmatter may declare `directories`,
`links`, `copies`, `seeds`, `resets`, `packages`, `level`, `phase`, `hosts`, and platform scopes such as `all`,
`linux`, and `macos`.

`phase: early` is reserved for small prerequisite-style modules that must unblock later actions in the same apply run;
ordinary modules use the default `normal` phase.

Link sources are repository-relative by default. A source beginning with `~/` or `/` is a target-home source for
managed links between live home paths. Dropbox-to-Dropbox links are written relative to the target directory.

Recommended module sections:

```text
## Prerequisites
## Install
## Post Install
## Configure
## Update
## Notes
```

Platform-specific actions use a platform heading with normal action sections nested below it:

```text
## Linux
### Install

## MacOS
### Configure
```

These platform-scoped sections are enough to make the module applicable for that platform. Do not add placeholder
frontmatter entries just to force a platform section to run.

Code blocks must be idempotent or guarded. If an effect cannot be safely detected from live target facts, represent it
as a prerequisite, note, or explicit proposal-first operator action.

## Commands

`/tilde` is an agent prompt marker, not a shell command. Shell helpers go through the loaded runtime:

```sh
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
```

Do not rely on bare `tilde` on the controller `PATH`.

The public surface is deliberately small:

| Command | Kind | Use |
| --- | --- | --- |
| `deploy` | agent | Prepare a new or reset host and apply desired state. |
| `update` | agent | Refresh package managers, reconcile current desired state, and run `Update` sections. |
| `repair` | agent | Reapply desired state without package refreshes or `Update` sections. |
| `align` | dual | Reconcile links, directories, copies, seeds, and resets only. |
| `status` | runtime | Show fast repository bindings and applied anchors. |
| `doctor` | runtime | Diagnose state, repository, and managed-surface health. |
| `handoff` | runtime | Print and copy the sudo handoff command. |
| `help` | runtime | Show command help. |

There is no public `create`, `init`, `adopt`, `clean`, `organize`, or `upgrade` command. Keep those workflows as
ordinary proposal-first agent work until they are mature enough to deserve command semantics.

`update` options:

| Prompt | Meaning |
| --- | --- |
| `/tilde update` | Default update: system package-manager refresh plus desired-state reconciliation. |
| `/tilde update --managed` | Also refresh managed non-system package declarations. |
| `/tilde update --greedy` | Managed update plus broad package-manager upgrade actions. |
| `/tilde repair` | Desired-state convergence without package refreshes, broad upgrades, or `Update` sections. |

If target status shows missing `state.yml` or no `applied` anchors, an update workflow uses repair mode for that run to
recover bindings and anchors. Missing state is recovery, not proof that the host was never deployed.

Remote workflows always start with:

```sh
"$TILDE" preflight remote HOST --format json
```

Then run status, plan, apply, and final verification on the target through Tilde SSH transport. Remote plans must use
the target's `state.public` and `state.private` bindings; do not read the controller state file for a remote host.
Remote scripts are POSIX `sh` by default.

`align` is direct only for the current host. Remote align is a prompt workflow implemented as target-local
`plan --mode align --format json` plus `tilde apply`.

Example prompts:

```text
/tilde deploy
/tilde deploy spinoza
/tilde update
/tilde update --managed
/tilde update --greedy
/tilde update spinoza
/tilde update ALL
/tilde update WORK
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

No proof means no destructive mutation. Managedness must be proven before removing links, spans, file
materializations, files, or packages.

Package manager state is the source of truth for package presence. Package inventories are ephemeral apply-time
optimizations only.

Package metadata refresh warnings about incomplete indexes, signature failures, missing repository keys, or failed
source fetches are deferred, even when the package manager exits successfully.

One-off operator workflows stay outside the desired-state model. Tilde may assist with checks and execution.

If a run times out or reports `state lock busy`, do not remove the lock file blindly. First verify that no Tilde/apply
process is active on the target; otherwise treat the run as deferred and retry later.

## References

- [Specification](references/specification.md)
- [Repository Development](references/development.md)
