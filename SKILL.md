---
name: tilde
description: Use for Tilde deployment, provisioning, and home-management work. Trigger for `$tilde ...`, `~ ...`, messages whose first word is `tilde`, or requests to create, initialize, deploy, update, diagnose managed state, adopt app/config files, customize data-layer policy, or work with Tilde home behavior.
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

When the user invokes `$tilde <command> [ssh:<host>] [qualifiers...]`:

1. Treat `$tilde` as an agent prompt contract. Do not assume every command is a direct shell route.
2. Identify the target: local host or `ssh:<host>`.
3. Classify the command from the Command Reference below.
4. Map agent-orchestrated commands to the Workflow Matrix before running helpers.
5. For remote targets, use `tilde ssh HOST` for script delivery. Generate plans, run live checks, and apply results on
   the target host, not on the controller.
6. Keep proposal-first behavior for destructive, preference-sensitive, privilege-requiring, or remote mutations.
7. After the run, summarize successful, changed, deferred, conflicted, and failed work.

If a direct runtime call says a command is agent-orchestrated, stop trying shell variants of that command. Load this
skill, classify the command, and run the appropriate agent workflow.

## Runtime

The PATH-visible runtime surface is `bin/tilde`, `bin/sudo`, and helper commands intentionally exposed in the Tilde
runtime PATH. Normal command implementations live in `libexec/` and are dispatched through `bin/tilde`.

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

These commands have direct `bin/tilde` runtime routes. For remote targets, deliver the command through `tilde ssh HOST`
so the target host supplies live facts.

- `help`: show public commands or one command's usage.
- `doctor`: diagnose state, repository, target, and managedness problems without executing module code or mutating
  targets.
- `handoff`: copy and print the privilege handoff command for the local or remote host.
- `status`: show compact repository bindings and last fully converged anchors.

### Dual Command

- `align`: local link/copy reconciliation can run directly as `tilde align`. Remote align remains agent-orchestrated:
  use `$tilde align ssh:<host>` semantics and deliver the target-side workflow through `tilde ssh HOST`.

### Implementation Routes

- `ssh`: deliver scripts to a remote host with the Tilde runtime environment active.
- `plan`: produce a plan from current committed repository content and target-host facts.
- `apply`: apply one or more plan files.
- `sudo`: classify privilege needs and support handoff.
- `boot`, `checkout`, `preflight`, and `smoke`: specialized runtime helpers.

Do not present implementation routes as user-facing `$tilde` commands. When using them, prefer undotted route names such
as `tilde plan` and `tilde apply`.

## Workflow Matrix

Agent commands map to planning modes and module sections as follows.

| Prompt command | Plan mode | Module behavior |
| --- | --- | --- |
| `deploy` | `apply` | `Prerequisites`, `Install`, `Post Install` when `Install` changed, then `Configure` |
| `update` | `refresh` | `Prerequisites`, `Update`, then `Configure` |
| `repair` | `repair` | `Prerequisites`, `Install`, `Post Install` when `Install` changed, then `Configure` |
| `upgrade` | `upgrade` | explicit broad update/upgrade behavior |
| `align` | `align` | links and copies only; no bootstrap, packages, or module code |

`create`, `init`, `clean`, `organize`, and `adopt` are proposal-first operator workflows unless a direct helper is
explicitly documented for the requested step.

The prompt command is `update`; the plan mode is `refresh`. Do not call or invent `--mode update`.

## Remote Script Execution

Use `bin/tilde ssh HOST` for all remote script execution. It sets up the
correct Tilde runtime environment (PATH, TILDE_ROOT, TILDE_SUDO, locale) and
delivers the script body through `ssh HOST sh -s --`.

Do not use raw `ssh`, `sh -c`, or `bash -lc` for multi-command remote work.
These bypass Tilde's PATH setup and sudo interceptor.

Always plan and execute on the target host. Platform detection, package inventory, repository bindings, and live checks
come from the target. A controller-side plan for a remote host is invalid.

```bash
tilde ssh HOST << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

tilde plan --mode refresh --repo ~/Dropbox/home --host HOST --format json > "$tmpdir/public.json"
tilde plan --mode refresh --repo ~/Dropbox/home- --host HOST --format json > "$tmpdir/private.json"
tilde apply --plan "$tmpdir/public.json" --plan "$tmpdir/private.json"
SCRIPT
```

Replace repository paths with the target host's configured bindings. Omit the private plan when the target has no
private repository.

When the script needs Bash features, pass the interpreter as an argument:

```bash
tilde ssh HOST -- bash << 'SCRIPT'
# bash-specific syntax here
SCRIPT
```

Use `tilde ssh --tty HOST` for interactive remote sessions that require a
pseudo-terminal (e.g., `sudo` password prompts).

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
bin/tilde handoff --host HOST --copy
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
- Do not run `tilde update`, `tilde deploy`, or `tilde repair` as direct shell routes; these are prompt workflows.
- Use `tilde plan --mode refresh` for the implementation of the `update` prompt command.
- Remove packages, copies, files, or spans only with explicit managedness proof and proposal-first confirmation.
- Prefer a safe `deferred` or `conflict` result over guessing.
