# Tilde

Tilde is an agent skill and control plane for reconciling a host with desired state stored in public and private home
repositories. The canonical contract is [references/specification.md](references/specification.md). That specification
defines the stateless provisioning model used by the skill and runtime helpers.

- Tilde primarily targets Linux and macOS hosts.
- After the base system bootstrap, most user tools are installed with Homebrew on both platforms.
- Linux desktop hosts additionally use Flatpak for desktop applications that are better managed outside Homebrew.
- The skill has been developed with Codex 5.5, but its workflow, guardrails, and deterministic helper routes are tuned
  for day-to-day use with Deepseek Flash V4, especially the max variant.

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
`links`, `copies`, `seeds`, `resets`, `packages`, `level`, `hosts`, and platform scopes such as `all`, `linux`, and
`macos`.

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

Code blocks must be idempotent or guarded. If an effect cannot be safely detected from live target facts, represent it
as a prerequisite, note, or explicit proposal-first operator action.

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

| Command    | Kind    | Action                                                                     |
| ---------- | ------- | -------------------------------------------------------------------------- |
| `help`     | runtime | Show public commands or one command's usage.                               |
| `deploy`   | agent   | Prepare a local or remote host and apply desired state.                    |
| `update`   | agent   | Run explicit update behavior from the current desired state.               |
| `repair`   | agent   | Apply current desired state again.                                         |
| `doctor`   | runtime | Diagnose without executing module code or mutating targets.                |
| `handoff`  | runtime | Copy and print the privilege handoff command for the local or remote host. |
| `align`    | dual    | Reconcile directories, links, copies, seeds, and resets without bootstrap or packages. |
| `adopt`    | agent   | Propose adopting an app, config, package, or path.                         |
| `create`   | agent   | Propose public/private home repository creation.                           |
| `init`     | agent   | Bind existing public/private repositories.                                 |
| `clean`    | agent   | Propose conservative cleanup.                                              |
| `organize` | agent   | Propose organization changes.                                              |
| `upgrade`  | agent   | Run the widest explicitly requested update path.                           |

Kind meanings:

- `agent`: interpreted by the loaded Tilde skill; no direct runtime route.
- `runtime`: direct `bin/tilde` route. For remote targets, run it on the target through Tilde SSH transport.
- `dual`: direct local runtime route plus prompt workflow. Remote targets are agent-orchestrated.

Remote `align` uses target-local `plan --mode align --format json` files followed by `tilde apply`; do not run
`tilde align --format json` on a remote target. Do not hide remote Tilde stderr with `/dev/null`; a non-zero remote exit
means the step failed, deferred, or conflicted even when stdout is empty. A later status read does not make an earlier
failed remote step successful.

After `tilde apply`, inspect action results. `completed: true` means all planned actions were processed, but the run is
incomplete if any action is `deferred`, `conflict`, or `notok`.

For agent workflows, `update` ordinarily maps to planning mode `refresh`. If target status shows missing `state.yml` or
no `applied` anchors, use `repair` mode for that run so state recovery writes recovered bindings and anchors without
running `Update` sections. Plans for remote hosts must be generated and applied on the target host. After a successful
mutating remote apply, read final status on the target before closeout. Materialize plan JSON under a per-run
`mktemp -d` directory and clean it with a trap; do not leave fixed files such as `/tmp/opencode/HOST-public.json`.
Successful Tilde-generated `refresh` plans advance `applied` anchors after every required action succeeds.

`update` / `refresh` reconciles current desired-state declarations, including newly declared packages, links, copies,
seeds, and resets. Use `repair` when the intent is desired-state convergence without package refreshes, package
upgrades, or `Update` sections.

For mutating remote workflows, first run:

```sh
"$TILDE" preflight remote HOST --format json
```

The JSON result is the source of truth for the initial bootstrap decision (`bootstrap.needed`), repository backend
(`backend`), runtime state, Dropbox runtime state, sudo cleanup state, and next steps. If the target
`~/.agents/skills/tilde` checkout is stale, refresh it from the controller checkout before running target
`tilde status`, `tilde plan`, or `tilde apply`. On Dropbox-backed hosts, prefer converting a clean matching provisional
runtime checkout into `~/.agents/skills/tilde -> ~/Dropbox/tilde` with `checkout runtime-link` once the Dropbox checkout
is current. On Git-backed remote hosts, also refresh stale public/private target checkouts from the controller
repositories before planning. If a stale target runtime or checkout cannot be safely refreshed, stop with `deferred`.
Status paths outside the `state.yml` model, such as `config.yml` or `hosts/HOST/state.md`, mean stale target runtime,
not successful state recovery. Use `checkout remote` with `--host`, `--repo`, and `--target`; the route does not infer
bindings from `--host`. Runtime freshness maps the loaded skill root to target `~/.agents/skills/tilde`; desired-state
freshness maps the selected data repository to the target binding. Quote target paths that start with `~` so the
controller shell does not expand them before the remote receives the path. Use `--replace-clean` only for a clean runtime
checkout with divergent history, not for desired-state checkouts without explicit operator approval.
For Git-backed targets, controller-side Dropbox paths are source paths, not target paths; do not create target-side
`~/Dropbox` for repository binding, cleanup, shared app state, or convenience paths unless active target policy says the
host has Dropbox-backed storage.

When active home policy requires Dropbox conflicted-copy cleanup, use only the literal cleanup root named by that policy,
normally `$HOME/Dropbox`. Do not additionally scan symlink-resolved or platform-specific Dropbox paths unless policy
names them.

For host-aware prompt commands, omitted target means current host. A bare host means `ssh:host`, except when it names
the current host; use explicit `ssh:host` to force SSH transport. Bare all-caps targets such as `ALL`, `HOME`, and
`WORK` are host groups defined by the active home policy. For remote workflows, target state is also read on the target
host. Do not use the controller's `~/.local/state/tilde/state.yml` to discover remote repository bindings, applied
anchors, level, platform, or bootstrap state.

For explicitly requested configured host groups, report the expanded host list and continue; do not ask for permission
to start the requested workflow. Ask only when the group is undefined, ambiguous, unexpectedly expands outside active
policy, or a later step requires separate explicit confirmation. Host-group reachability probes use Tilde SSH
transport, not raw `ssh`. Tilde SSH loads non-secret `~/.config/environment.d/*.conf` values before the remote script
body. After remote runtime freshness is verified, read target `tilde status --format json`, bind `state.public` /
`state.private` to shell variables, and use those variables for target-local plan paths instead of retyping
host-convention paths.

Example prompts:

```text
/tilde deploy
/tilde deploy spinoza
/tilde update
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
