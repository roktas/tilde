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

## Runtime

The PATH-visible runtime surface is `bin/tilde`, `bin/sudo`, and helper commands intentionally exposed in the Tilde
runtime PATH. Normal command implementations live in `libexec/` and are dispatched through `bin/tilde`.

Use `bin/tilde ssh HOST` for Tilde-controlled remote script delivery when available. It sends a script body through
`ssh HOST sh -s --`; do not compose multi-command remote work with `ssh HOST 'set -e; ...'`, `sh -c`, or `bash -lc`
unless the target entrypoint explicitly requires Bash.

## Public Commands

- `help`: show public commands or one command's usage.
- `deploy`: prepare a local or remote host and apply desired state.
- `update`: run explicit update behavior from the current desired state.
- `repair`: apply the current desired state again; it does not read a repair queue or module-level state.
- `doctor`: diagnose state, repository, target, and managedness problems without executing module code or mutating
  targets.
- `handoff`: copy and print the privilege handoff command for the local or remote host.
- `align`: reconcile links and copies without bootstrap, packages, or module code.
- `adopt`: inspect a requested app, config, package, or path and propose public/private repository placement.
- `create`, `init`, `clean`, `organize`, and `upgrade`: follow the specification and user policy; keep destructive or
  preference-sensitive work proposal-first.

Treat `dry-run` and `plan-only` as qualifiers. Do not invent a separate stateful planning model for them.

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
bin/tilde handoff --host HOST
```

The helper prints the exact command and reports whether it copied the command to the controller clipboard. Wait for the
user to run it, then rerun the affected action and verify cleanup. Do not collect passwords in chat.

## Weak-Model Guardrails

For weaker or low-context agents:

- Plan from current committed repositories and targeted live facts.
- Treat `Prerequisites` as read-only checks.
- Advance `applied` anchors only after every required action succeeds.
- Keep `applied` anchors unchanged after `deferred`, `conflict`, or `notok`.
- Remove packages, copies, files, or spans only with explicit managedness proof and proposal-first confirmation.
- Prefer a safe `deferred` or `conflict` result over guessing.
