---
name: tilde
description: Use for Tilde deployment, provisioning, and home-management work. Trigger for Tilde prompt markers such as `/tilde ...` or `$tilde ...`, `~ ...`, messages whose first word is `tilde`, or requests to create, initialize, deploy, update, diagnose managed state, adopt app/config files, customize data-layer policy, or work with Tilde home behavior.
---

# Tilde

Tilde is a standalone agent skill and control plane. The canonical contract is
[Specification](references/specification.md). Read that file before changing behavior or executing nontrivial Tilde
work. The `.agents/specs/tilde.md` path is only a symlink to the same canonical file.

The provisioning model is:

- Desired state comes from the current committed public/private home repositories.
- The only persistent Tilde state file is `~/.local/state/tilde/state.yml`.
- `state.yml` stores repository bindings and the last fully converged commit anchors.
- Planning evaluates current manifests and targeted live facts on every run.
- Every run compares current desired manifests with targeted live checks and idempotent actions.
- Failed, conflicted, or deferred runs do not advance `applied` anchors.

When existing docs, code, habits, or memory conflict with `references/specification.md`, the specification wins.

## Agent Quickstart

When the user invokes a Tilde prompt such as `/tilde <command> [target] [qualifiers...]`:

1. Treat `/tilde`, `$tilde`, and similar Tilde prompt markers as agent prompt contracts. They are not shell commands.
2. Resolve the controller-side runtime entrypoint before shell execution. Use the loaded skill directory's `bin/tilde`;
   if that path is not available, use `~/.agents/skills/tilde/bin/tilde`. Do not rely on bare `tilde` being on `PATH`.
3. Identify the target: current host, `host`, `ssh:host`, or an all-caps host group such as `ALL`, `HOME`, or `WORK`.
4. Classify the command from the Command Reference below.
5. Map agent-orchestrated commands to the Workflow Matrix before running helpers.
6. For remote targets, use the resolved runtime entrypoint for script delivery. Generate plans, run live checks, and
   apply results on the target host, not on the controller.
7. Keep proposal-first behavior for destructive, preference-sensitive, privilege-requiring, or remote mutations.
8. After a successful mutating remote apply, run a cheap final status read on the target before closeout.
9. After the run, summarize successful, changed, deferred, conflicted, and failed work.

If a direct runtime call says a command is agent-orchestrated, stop trying shell variants of that command. Load this
skill, classify the command, and run the appropriate agent workflow.

Do not execute `/tilde ...` or `$tilde ...` in a terminal. `/tilde` is a prompt marker, and `$tilde` may be a Codex skill
trigger or shell variable expansion depending on the environment. Shell execution uses the resolved runtime entrypoint,
written as `"$TILDE"` in examples:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" help
"$TILDE" ssh spinoza
```

If the skill was loaded from another directory, set `TILDE` to that directory's `bin/tilde` instead. If a controller-side
`tilde` command is not found, do not search the filesystem for it; switch to the resolved runtime entrypoint.

For remote targets, the first target-state read must happen on the target through Tilde SSH transport. Do not
inspect the controller's `~/.local/state/tilde/state.yml` to discover a remote host's repository bindings, applied
anchors, level, platform, or bootstrap state. That file belongs only to the controller host.

## Target Grammar

Host-aware prompt commands accept these target forms:

- no target: current host, also called localhost.
- `host`: remote host shorthand for `ssh:host`.
- `ssh:host`: explicit remote host target.
- `GROUP`: a bare all-caps host group defined by the active home policy, such as `ALL`, `HOME`, or `WORK`.

The host-aware prompt commands are `deploy`, `update`, `repair`, `upgrade`, `align`, `status`, and `doctor`.
Commands with their own subject syntax, such as `adopt APP_OR_PATH`, `clean SUBJECT`, `organize SUBJECT`, `create`, and
`init`, do not treat a bare argument as a host unless the command's own policy says so.

Bare all-caps targets are not hostnames. Expand them from the active `~/AGENTS.md` home policy before running any remote
work. Group expansion applies only to unprefixed target tokens; `ssh:host` is always an explicit host target. If the
policy does not define the requested group, ask the user for the host list. For mutating commands, present the expanded
host list and obtain confirmation before applying changes. Run each host as a separate target workflow and report
per-host results.

When traversing a host group, perform a bounded noninteractive reachability check before each host workflow. Skip
unreachable hosts and continue with the remaining hosts. Report skipped hosts separately; an unreachable host inside a
group is not a failure for reachable hosts. If every expanded host is unreachable, stop with a clear `deferred` result.

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
host=spinoza
"$TILDE" ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" << 'SCRIPT'
printf 'ok\n'
SCRIPT
```

## Runtime

The PATH-visible runtime surface is `bin/tilde`, `bin/sudo`, and helper commands intentionally exposed in the Tilde
runtime PATH. Normal command implementations live in `libexec/` and are dispatched through `bin/tilde`.

Controller-side runtime calls must go through the resolved entrypoint. Bare `tilde` is valid only when the Tilde runtime
PATH is already active, such as inside a remote script delivered by Tilde SSH transport.

`bin/tilde` has direct runtime routes for helper and diagnostic commands. It intentionally refuses prompt commands such
as `update`, `deploy`, and `repair`; those commands are interpreted and orchestrated by the loaded Tilde skill.

Implementation routes such as `plan` and `apply` are stable primitives for agent workflows. They are not user-facing
prompt commands. Use them only inside the workflow patterns in this skill and the specification.

## Command Reference

Commands are grouped by execution model.

### Agent-Orchestrated Prompt Commands

The agent interprets these high-level commands and orchestrates the workflow. They have no direct runtime route.

- `deploy`: prepare a local or remote host and apply desired state.
- `update`: run explicit update behavior from the current desired state.
- `repair`: apply the current desired state again; it does not read a repair queue or module-level state.
- `upgrade`: run the widest explicitly requested upgrade path.
- `adopt`: inspect a requested app, config, package, or path and propose public/private repository placement.
- `create`, `init`, `clean`, and `organize`: follow the specification and user policy; keep destructive or
  preference-sensitive work proposal-first.

Treat `dry-run` and `plan-only` as qualifiers. Do not invent a separate stateful planning model for them.

### Direct Runtime Commands

These commands have direct `bin/tilde` runtime routes. For remote targets, deliver the command through
Tilde SSH transport so the target host supplies live facts.

- `help`: show public commands or one command's usage.
- `doctor`: diagnose state, repository, target, and managedness problems without executing module code or mutating
  targets.
- `handoff`: copy and print the privilege handoff command for the local or remote host.
- `status`: show compact repository bindings and last fully converged anchors.

### Dual Command

- `align`: local link/copy reconciliation can run directly through the resolved runtime entrypoint. Remote align remains
  agent-orchestrated: use `/tilde align spinoza` prompt semantics and deliver the target-side workflow through Tilde SSH
  transport.

### Implementation Routes

- `ssh`: deliver scripts to a remote host with the Tilde runtime environment active.
- `plan`: produce a plan from current committed repository content and target-host facts.
- `apply`: apply one or more plan files.
- `sudo`: classify privilege needs and support handoff.
- `boot`, `checkout`, `preflight`, and `smoke`: specialized runtime helpers.

Do not present implementation routes as user-facing Tilde prompt commands. When using them on the controller, use the
resolved runtime entrypoint with undotted route names such as `"$TILDE" plan` and `"$TILDE" apply`.

## Workflow Matrix

Agent commands map to planning modes and module sections as follows.

| Prompt command | Plan mode | Module behavior |
| --- | --- | --- |
| `deploy` | `apply` | `Prerequisites`, `Install`, `Post Install` when `Install` changed, then `Configure` |
| `update` | `refresh` | `Prerequisites`, `Update`, then `Configure` |
| `repair` | `repair` | `Prerequisites`, `Install`, `Post Install` when `Install` changed, then `Configure` |
| `upgrade` | `upgrade` | broad refresh behavior, then package upgrades |
| `align` | `align` | links and copies only; no bootstrap, packages, or module code |

`create`, `init`, `clean`, `organize`, and `adopt` are proposal-first operator workflows unless a direct helper is
explicitly documented for the requested step.

The prompt command is `update`; the plan mode is `refresh`. Do not call or invent `--mode update`.

## Remote Script Execution

Use the resolved runtime entrypoint for all remote script execution:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza
```

It sets up the correct Tilde runtime environment (PATH, TILDE_ROOT, TILDE_SUDO, locale) and delivers the script body
through `ssh host sh -s --`.

Do not use raw `ssh`, `sh -c`, or `bash -lc` for multi-command remote work.
These bypass Tilde's PATH setup and sudo interceptor.

Always plan and execute on the target host. Platform detection, package inventory, repository bindings, and live checks
come from the target. A controller-side plan for a remote host is invalid.

Remote state is target-local. For `/tilde update spinoza`, `/tilde update ssh:spinoza`, `/tilde deploy spinoza`,
`/tilde deploy ssh:spinoza`, `/tilde doctor spinoza`, `/tilde status spinoza`, and `/tilde align spinoza`, do not read the controller's
`~/.local/state/tilde/state.yml`. If state or repository bindings are needed, read them on the target:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

tilde plan --mode refresh --repo ~/Dropbox/home --host spinoza --format json > "$tmpdir/public.json"
tilde plan --mode refresh --repo ~/Dropbox/home- --host spinoza --format json > "$tmpdir/private.json"
tilde apply --plan "$tmpdir/public.json" --plan "$tmpdir/private.json"
SCRIPT
```

Replace repository paths with the target host's configured bindings. Omit the private plan when the target has no
private repository.

After a successful mutating remote apply, verify target convergence with a separate cheap status read so the apply JSON
stays easy to parse:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

Use `target HEAD` or `target current commit` for the repository commit currently checked out on the remote host. Use
`applied anchor` for the commit recorded under `applied` in the target's `state.yml`. Do not call a remote repository
HEAD `local` in summaries; that word is ambiguous from the controller.

Inside the remote script body, bare `tilde` is valid because Tilde SSH transport places the target runtime directory at
the front of `PATH`.

When the script needs Bash features, pass the interpreter as an argument:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza -- bash << 'SCRIPT'
# bash-specific syntax here
SCRIPT
```

Use `"$TILDE" ssh --tty spinoza` for interactive remote sessions that require a pseudo-terminal (e.g., `sudo` password
prompts).

## Module Model

Module README code sections use this stateless contract:

- `Prerequisites`: external requirements and read-only checks only. Failed checks return `deferred`.
- `Install`: idempotently ensure packages, tools, directories, applications, repositories, or local resources are present.
- `Post Install`: runs only when `Install` changed something in the current run; correctness must not depend on it.
- `Configure`: idempotent desired configuration and drift repair.
- `Update`: explicit refresh or upgrade work.
- `Notes`: informational only; never executed.

Code blocks must be idempotent or guarded. If an effect cannot be detected from live target facts, represent it as a
prerequisite, note, or explicit proposal-first operator action.

Package managers are the source of truth for package presence. Package inventories are ephemeral, in-memory
optimizations only.

Module code blocks call Tilde helpers by their plain names, such as `line` and `span`. Privileged helper calls use the
same plain form with `sudo`, such as `sudo line ...`.

## Safety

Proposal-first behavior is required before replacing unmanaged files, removing stale links or managed spans, backing up
conflicting paths, uninstalling packages, running non-idempotent code, requiring privileges, mutating remote hosts, or
performing one-off operator workflows.

Managedness must be proven before destructive cleanup. No proof means no destructive mutation.

If sudo is required and noninteractive sudo fails, report `deferred` and present:

```bash
"$TILDE" handoff --host spinoza --copy
```

The helper prints the exact command and reports whether it copied the command to the controller clipboard. Wait for the
user to run it, then rerun the affected action and verify cleanup. Do not collect passwords in chat.

## Weak-Model Guardrails

For weaker or low-context agents:

- Plan from current committed repositories and targeted live facts.
- Treat `Prerequisites` as read-only checks.
- Advance `applied` anchors only after every required action succeeds.
- Keep `applied` anchors unchanged after `deferred`, `conflict`, or `notok`.
- Never plan a remote host from the controller.
- Never read controller `~/.local/state/tilde/state.yml` for a remote target.
- Never execute `/tilde ...` or `$tilde ...` in a shell; they are prompt markers, not runtime commands.
- Before any controller-side runtime call, resolve `TILDE` to the loaded skill directory's `bin/tilde`, falling back to
  `~/.agents/skills/tilde/bin/tilde`.
- If bare `tilde` is not found on the controller, do not search for it; rerun through `"$TILDE"`.
- Do not run the `update`, `deploy`, or `repair` routes through `"$TILDE"`; these are prompt workflows.
- Use the `plan --mode refresh` implementation route for the `update` prompt command.
- For host-aware prompt commands, treat bare `host` as `ssh:host`; omitted target means current host.
- Treat bare all-caps targets such as `ALL`, `HOME`, and `WORK` as home-policy host groups, not hostnames; ask the user
  if the active home policy does not define the requested group.
- When traversing a host group, skip unreachable hosts after a bounded reachability check and continue with reachable
  hosts.
- After a successful mutating remote apply, run a final target status read before the final answer.
- In remote summaries, distinguish `target HEAD` from `applied anchor`; do not call the target repository commit
  `local`.
- Remove packages, copies, files, or spans only with explicit managedness proof and proposal-first confirmation.
- Prefer a safe `deferred` or `conflict` result over guessing.
