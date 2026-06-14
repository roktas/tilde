# Tilde sudo and ssh runtime rationale

This note records the design rationale behind the routed SSH and sudo runtime. Canonical behavior lives in
`references/specification/`, `SKILL.md`, and `references/development.md`.

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
  doctor
  help
  plan
  preflight
  smoke
  ssh
  status
  sudo
```

The canonical command surface is `bin/tilde COMMAND ...`. Prefix executables such as `bin/tilde-apply`,
`bin/tilde-plan`, `bin/tilde-ssh`, or `bin/tilde-sudo` are not the preferred public model.

`bin/tilde` is the public dispatcher and router hub. It resolves the Tilde root, sets the Tilde execution environment,
normalizes global flags and diagnostics, and dispatches to `libexec/*`.

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

`bin/sudo` guards against accidental use. If `TILDE_SUDO` is not `intercept`, it fails closed with a clear configuration
error.

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

The wrapper writes the machine-readable marker `TILDE_PRIVILEGE_REQUIRED` to stderr, exits with the reserved status
`125`, and appends a JSONL event to a Tilde runtime log path supplied by `libexec/apply`. The log is useful because a
README block can swallow a sudo failure with shell logic such as `|| true`.

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

## Future Work

- `tilde sudo handoff` should support SSH transport options for targets that are not reachable through a plain SSH
  alias. Lima and `there` targets may require an SSH config file such as `ssh -F PATH HOST`. Prefer a small explicit
  option surface such as `--ssh-config PATH` and repeatable `--ssh-option OPTION`, while keeping the printed command
  short, visible, and copyable.
- Runtime routes such as `tilde ssh` are intentionally hidden from public help, but developer discovery should be
  clearer. Document route-specific help, such as `bin/tilde ssh --help` and `bin/tilde sudo --help`, without making
  internal runtime routes part of ordinary public `$tilde help`.
- Apply section execution should gain bounded runtime diagnostics for long-running or stuck commands. The spinoza update
  showed that a README section can appear silent while a child process is blocked. A lightweight heartbeat, current
  action marker, or configurable timeout would make remote recovery safer.
- Keep regression coverage for multiple Tilde path aliases in `PATH`. Dropbox, installed-skill symlinks, and explicit
  `tilde ssh --root` values can expose more than one `bin/sudo` shim to the same process; sudo resolution must skip all
  Tilde shims and select the real system sudo.
- Add a clearer repair path for completed apply runs that still contain `notok` results. The spinoza retry generated a
  smaller apply plan for failed modules and overwrote the deployment apply cache with that retry-sized result; status
  still had module state, but the apply cache no longer represented the full original action stream.
- Improve privilege-handoff ergonomics for multi-step repair sessions. Current cleanup behavior is correct and removes
  `/etc/sudoers.d/tilde` after each remote script, but package-repair failures required repeated handoff cycles. A
  future routed repair flow should keep cleanup strict while reducing repeated manual copy/paste.

## Field Notes

### 2026-06-14 kant update

`$tilde update ssh:kant` completed with a usable final state. Public and private data repositories were already clean
on the target, bootstrap state was present, and the update only had to apply changed desired state plus fast refresh.

Observed results:

- `public/macos` Postinstall deferred because the Screen Sharing `launchctl` command needs sudo in a non-interactive
  remote session.
- `brew refresh` upgraded formulae and the Codex desktop cask; Homebrew quit and reopened `Codex.app` as part of the
  cask upgrade.
- During the long refresh action, `last-refresh-apply.json` could still show the previous completed refresh until the
  first action result was recorded. The executor should write a fresh incomplete apply cache before starting the first
  action when no resumable cache is active.
- `status` reported "Last apply date" using the refresh timestamp. Deployment apply and refresh apply timestamps should
  be displayed separately so deferred deployment results are not obscured by a later successful refresh.
- Dropbox File Provider reported that the `home` and `home-` checkouts were not marked keep-downloaded. This did not
  block the update, but remote macOS runs should continue surfacing it because missing offline files can turn into
  confusing later failures.

Follow-up repair used `bin/tilde sudo handoff --host kant --copy`, the user ran the printed command, and `repair`
cleared the `public/macos` deferred result. Cleanup removed `/etc/sudoers.d/tilde` and verification showed the file was
absent. `launchctl load` emitted `Load failed: 5` while exiting successfully; `launchctl print` could see
`system/com.apple.screensharing` and localhost port `5900` was open. The macOS module should eventually make this
postinstall idempotence and diagnostic behavior clearer.

### 2026-06-14 spinoza update

- Bootstrap with temporary sudo handoff successfully installed the Linux Homebrew baseline and recorded bootstrap state.
- Desired-state apply then reached `public/linux:Install` and blocked in the first intercepted `sudo` call because
  `libexec/sudo` resolved another Tilde sudo shim as the real sudo through a different path alias.
- The sudo resolution fix let apply continue through the Linux, public, and private module actions. The later retry
  changed the previous `public/chrome:section:Install` and `private/codex:package:install:github:Lampese/codex-switcher`
  failures to `ok`.
- The fast refresh initially failed because apt was in a broken dependency state: `yazi` required Debian `fd-find`, while
  an existing unmanaged `fd` package owned `/usr/share/zsh/vendor-completions/_fd`. `apt-get -f install` could not
  resolve the file conflict until `dpkg -r fd` removed the unmanaged package.
- After `fd` was removed, `apt-get -f install` installed `fd-find`, configured the previously half-installed packages,
  and `apt-get check` passed inside the sudo handoff window.
- Final retry results were clean: deployment apply retry completed with `4 ok` and `7 unchanged`; fast refresh completed
  with `2 ok`; final checks reported `/etc/sudoers.d/tilde` absent, `sudo -n` requiring a password, and no stuck apply
  processes.
- Residual warnings remained: duplicate Chrome apt sources under `chrome.list` and `google-chrome.list`, and repeated
  `LC_ALL=C.UTF-8` locale warnings in remote shell output.

## Implementation Sketch

1. `bin/tilde` is the canonical router hub.
2. Command implementations live under `libexec/`.
3. `boot` is the bootstrap route name; `bootstrap` remains a valid alias.
4. `bin/sudo` and `libexec/sudo` are guarded by `TILDE_SUDO=intercept`.
5. README shell block execution runs through the Tilde execution environment.
6. Section-level privilege classification uses stderr, status, and `TILDE_SUDO_LOG`.
7. `libexec/ssh` routes remote snippets through `tilde ssh`.

## Settled Preferences

Prefer `bin/tilde COMMAND ...` as the canonical routed surface. The public shape should be one controlled entrypoint,
not a family of prefixed executables. This keeps the command vocabulary short, gives future commands a shared runtime
envelope, and makes aliases, help, structured output, trace setup, and error normalization central. Direct `libexec/*`
execution is useful for tests and development, but not as the normal agent-facing contract.

Prefer fail-closed behavior for accidental `bin/sudo` use outside the Tilde execution environment. If `bin/sudo` is
visible but `TILDE_SUDO=intercept` is missing, that is either a Tilde runtime setup bug or an accidental PATH leak.
Transparent pass-through could hide a missing Tilde guard and reintroduce blocking sudo prompts inside apply. An explicit
diagnostic escape hatch such as `TILDE_SUDO=passthrough` can be considered only with a separate spec change.

Prefer end-of-run reporting as the default, but not blind continuation. A privilege failure should mark the current
action as `deferred` and stop dependent follow-up work in the same module, so later non-privileged actions do not fail
just because a required privileged setup step never happened. Independent modules can continue. The final report should
separate primary privilege blockers from secondary skipped or cascaded actions. If Tilde gains explicit cross-module
dependencies later, use `blocked_by` dependency metadata instead of module-level failure as the boundary. The dispatcher
or agent can still offer an interactive `stop-on-privilege` mode for remote sessions where the user is available and an
immediate handoff/resume cycle is cheaper.

Prefer both stderr/capture and an apply-owned JSONL event file. The stderr marker and reserved exit code provide fast
classification for simple failures. The JSONL file is needed for failures swallowed by shell logic such as
`sudo ... || true`. `libexec/apply` creates a temporary event file for the action or block, exports it as
`TILDE_SUDO_LOG`, reads it after execution, folds structured events into action diagnostics and `last-apply.json`, then
removes the raw file. Default policy: any recorded privilege failure makes the action `deferred`, even if the shell block
exits 0. Optional sudo needs an explicit future escape hatch rather than being inferred.
