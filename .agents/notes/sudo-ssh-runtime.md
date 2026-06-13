# Tilde sudo and ssh runtime draft

This note is a working draft, not canonical Tilde behavior. Promote settled decisions into
`references/specification/` and `references/development.md` after the model is implemented and validated.

Router hub basics are now canonicalized in `references/specification.md`,
`references/specification/commands.md`, `SKILL.md`, and `references/development.md`. The remaining sudo, SSH, and
`libexec/` layout details in this note are still draft.

## Problem

Tilde currently has two related but separate runtime problems:

- Remote orchestration rules live partly in agent instructions, so every agent must remember the same SSH shape,
  quoting rules, target-path rules, and environment setup.
- Privileged commands can appear both as package actions and inside README shell blocks. Tilde must not broker
  privilege, collect passwords, or install host sudo policy, but it must detect privilege failures without hanging.
- Prompt-level Tilde operations are still partly agent procedure rather than routed runtime behavior. This makes
  repeated work such as SSH transport, sudo classification, checkout preparation, plan generation, and apply result
  handling depend too much on the current agent's memory and shell composition.

The long-term privileged-execution solution belongs outside the Tilde skill layer. Until that exists, Tilde needs a
small runtime workaround that makes failures deterministic and gives the user a clear handoff path.

## Long-Term Direction

Tilde should become an agent-directed control plane with a routed, testable runtime. The skill layer still owns intent,
scope, confirmation, policy interpretation, and conversation with the user. Repeated operational mechanics should move
behind narrow commands that have stable inputs, stable outputs, and deterministic failure classes.

The first goal is an AI-friendly routed command family. Commands such as `tilde ssh`, `tilde checkout`, `tilde plan`,
and `tilde apply`, plus internal routes such as `tilde sudo`, should encode fragile mechanics once, instead of requiring
every agent to reconstruct them from prose instructions. The agent should route intent to a command and inspect
structured results, not synthesize SSH quoting, sudo detection, repository transport, or plan/apply glue each time.

The second goal is a more deterministic runtime. `plan` should turn desired state into an immutable action stream.
`apply` should validate and execute that stream without rediscovery, argument mutation, or fallback invention. The
runtime should write structured diagnostics and state so future `repair`, `status`, and remote orchestration can reason
from facts rather than chat memory.

This does not require Tilde to become a conventional standalone CLI. The skill remains valuable because home discovery,
adoption, policy, destructive confirmation, and human handoff are broader than a deterministic executor. The runtime
exists to make the risky and repetitive parts smaller, testable, and portable across agent sessions.

## Non-Goals

- Do not change the user's normal shell `PATH`.
- Do not make Tilde a privilege broker.
- Do not collect sudo passwords through chat, stdin, or generated prompts.
- Do not install or manage `/etc/sudoers.d` policy as normal Tilde behavior.
- Do not hide privilege failures as successful deployment.
- Do not replace the Tilde skill with a fully autonomous CLI that bypasses proposal-first agent behavior.
- Do not let `bin/tilde` become a large implementation script. Command-specific behavior belongs under `libexec/`.

## Proposed Layout

Only the Tilde execution environment prepends `bin/` to `PATH`.

```text
bin/
  tilde
  sudo

libexec/
  apply
  boot
  checkout
  help
  plan
  ssh
  sudo
```

The canonical command surface is `bin/tilde COMMAND ...`. Prefix executables such as `bin/tilde-apply`,
`bin/tilde-plan`, `bin/tilde-ssh`, or `bin/tilde-sudo` are not the preferred public model. Direct helper wrappers, when
present, are focused entrypoints, not separate command families.

`bin/tilde` is the public dispatcher and router hub. It resolves the Tilde root, sets the Tilde execution environment,
normalizes global flags and diagnostics, and dispatches to `libexec/*`.

Initial implementation note: the first router slice may dispatch to direct `bin/*` helper entrypoints while the
`libexec/` layout is built out.

`bin/sudo` is a shim visible only inside the Tilde execution environment. It delegates to the internal `tilde sudo`
route, which dispatches to `libexec/sudo`.

`libexec/sudo` wraps the system sudo command. It never asks for a password. It calls real sudo in non-interactive mode,
detects authentication, TTY, and policy failures, and emits a stable Tilde privilege-failure marker.

`libexec/ssh` is the only remote orchestration entrypoint. Skill instructions should say to use `tilde ssh` instead of
constructing raw SSH heredocs by hand.

`libexec/boot` is the bootstrap baseline-preparation route. It remains baseline preparation only; it does not solve
privilege.

## Router Hub Rationale

Prefer one router hub over many prefixed executables. Tilde commands are not independent Unix tools with unrelated
runtime assumptions. They are parts of one control plane and should share the same safety envelope.

The router hub centralizes:

- root discovery and version checks;
- `PATH`, `TILDE_ROOT`, `TILDE_SUDO`, trace, and log setup;
- global flag handling and output format policy;
- command discovery, help, and aliases;
- structured error normalization;
- activation of sensitive behavior such as SSH transport and sudo interception.

Language diversity is not a reason to split the public surface. `bin/tilde` can be a small shell dispatcher and still
`exec` Ruby, shell, or future implementations under `libexec/`. The language boundary belongs at the command
implementation, not in the public executable name.

The main risk is a "god script". The guardrail is strict: `bin/tilde` may own routing, shared environment setup, aliases,
and common diagnostics only. It must not absorb command-specific plan, apply, checkout, SSH, or sudo logic. Those
behaviors stay in `libexec/<command>` and are tested there.

`bin/sudo` is the intentional exception to the single-public-entrypoint rule because sudo interception depends on PATH
lookup inside README shell blocks and package handlers. It is not a user-facing Tilde command. It exists only as a shim
inside the Tilde execution environment, delegates to the internal `tilde sudo` route, and should fail closed outside that
environment.

## Runtime Environment

Tilde-controlled commands run with an explicit environment:

```text
TILDE_ROOT=<skill checkout>
TILDE_SUDO=intercept
TILDE_REAL_SUDO=<absolute real sudo path>
PATH=$TILDE_ROOT/bin:$PATH
```

Outside that environment, the user's shell and normal `sudo` behavior are unchanged.

`bin/sudo` should guard against accidental use. If `TILDE_SUDO` is not `intercept`, it should transparently delegate to
real sudo or fail with a clear configuration error. The safer default needs a final decision before implementation.

## SSH Runtime

`tilde ssh` should encode the existing remote-orchestration rules:

- Do not rely on the target login shell.
- Use the visible `ssh HOST sh -s` script delivery shape for multi-command remote work.
- Set target PATH explicitly.
- Distinguish controller paths from target paths.
- Pass target home, target state root, and repository paths explicitly.
- Activate the Tilde sudo shim only for Tilde-controlled remote execution.
- Preserve the existing Git bundle transport path for private `remote-git` checkouts.

This keeps prompt-level instructions short and makes remote behavior testable.

## Sudo Interception

The sudo shim is only a detector and normalizer.

Expected behavior:

- Successful sudo command: run the command and pass through status and output.
- Missing real sudo: return a structured privilege failure.
- Password, TTY, authentication, or policy failure: return a structured privilege failure.
- Other sudo command failures: preserve the original nonzero failure.

The wrapper should write a machine-readable marker to stderr and may also append a JSONL event to a Tilde runtime log
path supplied by `libexec/apply`. The log option is useful because a README block can swallow a sudo failure with shell
logic such as `|| true`.

Open detail: choose the marker and exit code. A reserved exit code such as `125` plus a marker such as
`TILDE_PRIVILEGE_REQUIRED` is a plausible first pass.

## Apply Semantics

Package actions already have structured command execution. README shell blocks need equivalent privilege
classification.

Target behavior:

- A README shell block runs with the Tilde execution `PATH`.
- A privilege marker or reserved exit code makes the section action `deferred`, not `notok`.
- The action diagnostics include the module id, section name, block index, original stderr/stdout, and reason
  `privilege required`.
- Tilde does not continue pretending desired state is complete. The module remains incomplete until repair/resume.

Two orchestration modes are possible:

- Stop at the first privilege failure and ask the user to perform the handoff.
- Continue independent actions, then summarize all privilege failures at the end.

The executor should probably only produce structured results. The agent or dispatcher should decide whether to stop
immediately or continue.

## Handoff

When privilege is required and the target cannot run sudo non-interactively, Tilde may present a user-run handoff
command. The handoff is an external workaround, not Tilde-managed privilege policy.

The handoff should:

- Be explicit about the target user and host.
- Create a temporary `/etc/sudoers.d/tilde` rule only after validation.
- Provide a matching cleanup command.
- Warn that the rule grants broad root privilege and must be removed after the run.

Open detail: decide whether Tilde should verify cleanup automatically when it already has non-interactive sudo, or only
ask/report.

## Implementation Sketch

1. Add `bin/tilde` dispatcher as the canonical router hub while keeping direct helper paths valid.
2. Put command implementations under `libexec/` where that separation reduces complexity.
3. Add `boot` as the bootstrap route name while keeping `bootstrap` valid.
4. Add `bin/sudo` and `libexec/sudo`, guarded by `TILDE_SUDO=intercept`.
5. Route README shell block execution through the Tilde execution environment.
6. Add section-level privilege classification and tests.
7. Add `libexec/ssh` and route remote snippets through `tilde ssh`.
8. Update skill/spec/development docs only after behavior is implemented and validated.

## Open Questions

- Should accidental `bin/sudo` use outside Tilde execution delegate to real sudo, or fail closed? Draft answer: fail
  closed.
- Should privilege failure stop the run immediately, or should apply finish independent actions and summarize? Draft
  answer: finish independent work, but stop dependent follow-up work.
- Should the sudo shim maintain a JSONL log so swallowed sudo failures are still detectable? Draft answer: use both a
  stderr marker and an apply-owned JSONL event file.
- What exact handoff command and cleanup command should be generated?
- Should handoff state be represented in `last-apply.json`, host `state.md`, or both?
- How should `repair` resume after a user installs and later removes temporary sudoers policy?
- Should `tilde ssh` expose only high-level operations, or also a low-level script transport for diagnostics?
- Which direct `bin/*` helper entrypoints should remain available after the router hub lands?
- Should direct `libexec/*` invocation be supported for tests only, or treated as a stable internal interface?

## Current Preferences

Prefer `bin/tilde COMMAND ...` as the canonical routed surface. The public shape should be one controlled entrypoint,
not a family of prefixed executables. This keeps the command vocabulary short, gives future commands a shared runtime
envelope, and makes aliases, help, structured output, trace setup, and error normalization central. Direct `bin/plan`,
`bin/apply`, or other helper entrypoints may remain available for focused use. Direct `libexec/*` execution is useful
for tests and development, but not as the normal agent-facing contract.

Prefer fail-closed behavior for accidental `bin/sudo` use outside the Tilde execution environment. If `bin/sudo` is
visible but `TILDE_SUDO=intercept` is missing, that is either a Tilde runtime setup bug or an accidental PATH leak.
Transparent pass-through could hide a missing Tilde guard and reintroduce blocking sudo prompts inside apply. A future
explicit diagnostic escape hatch such as `TILDE_SUDO=passthrough` can be added if needed, but the default should be a
clear configuration failure. This is the current draft decision unless the runtime model changes.

Prefer end-of-run reporting as the default, but not blind continuation. A privilege failure should mark the current
action as `deferred` and stop dependent follow-up work in the same module, so later non-privileged actions do not fail
just because a required privileged setup step never happened. Independent modules can continue. The final report should
separate primary privilege blockers from secondary skipped or cascaded actions. If Tilde gains explicit cross-module
dependencies later, use `blocked_by` dependency metadata instead of module-level failure as the boundary. The dispatcher
or agent can still offer an interactive `stop-on-privilege` mode for remote sessions where the user is available and an
immediate handoff/resume cycle is cheaper.

Prefer both stderr/capture and an apply-owned JSONL event file. The stderr marker and reserved exit code provide fast
classification for simple failures. The JSONL file is needed for failures swallowed by shell logic such as
`sudo ... || true`. `libexec/apply` should create a temporary event file for the action or block, export it as
`TILDE_SUDO_LOG`, read it after execution, fold structured events into action diagnostics and `last-apply.json`, then
remove the raw file unless trace/debug retention is enabled. Default policy: any recorded privilege failure makes the
action `deferred`, even if the shell block exits 0. Optional sudo should need an explicit future escape hatch rather
than being inferred.
