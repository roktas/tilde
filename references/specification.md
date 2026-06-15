# Tilde Stateless Provisioning Specification

## 1. Purpose

Tilde is an agent skill and control plane for reconciling a host with desired state stored in public and private home repositories.

This specification defines the stateless provisioning model used by Tilde. Desired state is derived from the current committed repository content. Runtime state is intentionally minimal and must not become a source of desired state.

The model is based on:

- current desired manifests,
- targeted live checks,
- idempotent actions,
- proposal-first mutation,
- ephemeral apply-time facts,
- a single persistent state file,
- host-local locking,
- and explicit operator control for one-off workflows.

## 2. Core Invariants

Tilde evaluates the current desired state and targeted live facts on every run. Runtime state records the last fully
converged repository anchors for the host.

Runtime state answers:

> Which repository commits were last fully converged on this host?

Current planning answers:

> Which modules or actions are safe to skip?

For every run, Tilde derives desired state from the active public/private repositories and compares that desired state with targeted live facts from the host.

```text
committed repositories -> desired manifest
desired manifest + targeted live facts -> actions/results
```

## 3. Persistent State

Tilde keeps exactly one persistent state file:

```text
~/.local/state/tilde/state.yml
```

The state file is the complete persistent runtime state for correctness. Other apply-time facts are ephemeral.

The state file records repository bindings and the last fully applied commit anchors.

Example:

```yaml
protocol: tilde/v1
skill: ~/.agents/skills/tilde
public: ~/Dropbox/home
private: ~/Dropbox/home-

applied:
  level: normal
  platform: macos
  public: abc123
  private: def456
```

The `applied` section records:

> The listed public/private commit pair was fully reconciled on this host at the listed level and platform.

Module convergence is established from current live checks during each run.

### 3.1 Anchor Advancement

The `applied` anchors are advanced only after a fully successful desired-state run.

Successful statuses for anchor advancement are:

```text
ok
changed
unchanged
removed
skipped
ignored
```

The anchors MUST NOT advance if any required action returns:

```text
deferred
conflict
notok
```

A partially successful run leaves the previous `applied` anchors unchanged.

The anchor represents:

```text
last fully converged desired state
```

not:

```text
last attempted desired state
```

### 3.2 Locking and Atomic Writes

Tilde MUST acquire a host-local lock before mutating targets or writing `state.yml`.

Recommended lock path:

```text
~/.local/state/tilde/lock
```

The lock is runtime coordination, not desired-state memory.

If a lock cannot be acquired because another Tilde process is active, Tilde MUST return a clear lock-busy or `deferred` result and MUST NOT mutate targets.

`state.yml` MUST be written atomically:

1. write a temporary file in the same directory,
2. flush/fsync when practical,
3. rename over `state.yml`.

## 4. Dirty Repository Semantics

A desired-state repository is dirty when tracked desired-state content differs from `HEAD`.

Dirty states include:

- modified tracked files,
- deleted tracked files,
- renamed tracked files,
- staged but uncommitted changes,
- index differences from `HEAD`.

Untracked files do not make a desired-state repository dirty by default because they are not part of the committed desired tree.

Tilde MUST NOT include untracked files in the desired manifest unless an explicit mode requests it.

Untracked files under recognized desired-state paths MAY be reported by status or doctor as warnings, but they MUST NOT block commit-anchor advancement by default.

Default behavior:

```text
dirty tracked content -> no anchor advancement
```

Normal mutating apply SHOULD refuse dirty tracked repositories unless the user explicitly allows dirty operation. When dirty operation is explicitly allowed, Tilde MUST NOT advance commit anchors unless the exact applied tree identity can be represented safely.

## 5. Action Statuses

Tilde actions and helper commands use the following status vocabulary:

```text
ok          action completed successfully
changed     helper completed and changed a target
unchanged   target was already in the desired state
removed     helper removed a managed item
skipped     action/helper intentionally performed no change
ignored     action was intentionally not applicable in this mode
deferred    action requires external input, privilege, or unavailable host state
conflict    action found a condition requiring user/agent decision
notok       action failed
```

`conflict` actions MUST fail closed and MUST NOT modify the target that produced the conflict.

## 6. Planning

Planning always reads current committed repository content.

Planning MUST NOT skip a module because prior runtime state says the module was previously successful.

Planning produces a desired manifest for the selected host, platform, level, and command mode.

The manifest may include:

- links,
- copies,
- package declarations,
- helper-based file patches,
- executable fenced blocks,
- prerequisite checks,
- stale cleanup candidates derived from commit diffs.

## 7. Command Matrix

Tilde has three command surfaces:

- Prompt commands are user/agent workflows written as `$tilde COMMAND ...`.
- Runtime routes are direct `bin/tilde` helper commands.
- Implementation routes are runtime primitives used inside an agent workflow.

Prompt commands such as `deploy`, `update`, `repair`, `upgrade`, `adopt`, `create`, `init`, `clean`, and `organize` are
interpreted by the loaded Tilde skill. They are not guaranteed to have a direct runtime route.

Direct runtime commands such as `help`, `doctor`, `handoff`, and `status` may be run through `bin/tilde`. For remote
targets, the command must run on the target host through the Tilde SSH transport.

`align` is both a local runtime command and a prompt workflow. Remote align is agent-orchestrated.

Implementation routes such as `ssh`, `plan`, `apply`, `sudo`, `boot`, `checkout`, `preflight`, and `smoke` are stable
runtime primitives. They are not user-facing prompt commands.

Tilde planning modes execute module sections according to this matrix.

```text
prompt command -> plan mode
  deploy  -> apply
  update  -> refresh
  repair  -> repair
  upgrade -> upgrade
  align   -> align
```

The prompt command is `update`; the planning mode is `refresh`. Implementations MUST NOT invent a `--mode update`.

```text
apply / install:
  Prerequisites
  Install
  Post Install, only if Install changed in the current run
  Configure

refresh / update:
  Prerequisites
  Update
  Configure

repair:
  Prerequisites
  Install
  Post Install, only if Install changed in the current run
  Configure

align:
  links and copies only
  no bootstrap, packages, or module code

doctor:
  execute nothing
  diagnostics only
```

`doctor` MUST NOT execute module code blocks.

Privilege handoff:

```text
handoff
```

`handoff` prints the exact privilege-preparation command for the local or selected remote host and attempts to copy it
to the controller clipboard using a platform-appropriate clipboard command.

## 8. Module Sections

Recommended module README section order:

```text
## Prerequisites
## Install
## Post Install
## Configure
## Update
## Notes
```

Sections not relevant to a module may be omitted.

### 8.1 Prerequisites

`Prerequisites` describes blocking external conditions required before a module can be fully applied.

Examples:

- Dropbox must be installed and signed in.
- Xcode Command Line Tools must be installed.
- A hardware token must be connected.
- GitHub authentication must be available.
- A GUI installer or license prompt must be completed.

`Prerequisites` content is not an apply block.

`Prerequisites` MAY include read-only check blocks. A prerequisite check block MUST NOT mutate the target system.

A successful check means the prerequisite is satisfied. A failed check means the prerequisite is unsatisfied and the run returns `deferred`.

Prerequisite completion is not recorded in persistent state. It must be verified from live target facts.

Example:

````markdown
## Prerequisites

Dropbox must be installed, signed in, and synced.

```bash
test -d "$HOME/Dropbox/home"
```
````

### 8.2 Install

`Install` ensures that required packages, tools, directories, applications, repositories, and local resources are present.

`Install` does not mean first install only.

`Install` means:

```text
ensure installed / ensure present
```

Install blocks and package handlers MUST be idempotent or safely repeatable.

If the target is already present, Install returns `unchanged`.

If Install creates or installs something in the current run, Install returns `changed` or `ok` as appropriate. A changed Install phase enables `Post Install` for the same module in that run.

### 8.3 Post Install

`Post Install` contains install-event hooks that run only when the module's Install phase changed something in the current run.

If Install is `unchanged`, `Post Install` is skipped.

`Post Install` is an optimization and event hook. It is not a correctness layer.

Required final configuration MUST live in `Configure`, not only in `Post Install`.

`Post Install` blocks SHOULD still be guarded or idempotent because later failures may prevent commit-anchor advancement and cause the run to be retried.

### 8.4 Configure

`Configure` contains idempotent configuration and reconciliation steps.

`Configure` is the correctness layer for desired configuration.

It runs after Install in apply/install and repair modes, and after Update in update mode.

Examples:

- ensure shell configuration lines,
- ensure managed spans,
- prepare local directories,
- reconcile application configuration,
- ensure default files exist,
- repair configuration drift.

`Configure` blocks MUST be idempotent or guarded.

### 8.5 Update

`Update` contains explicit refresh or upgrade actions.

`Update` is not part of ordinary apply unless update mode is explicitly requested.

Examples:

- upgrade an installed tool,
- pull an external repository,
- refresh a generated cache,
- update a language tool installation.

`Update` blocks MUST be idempotent or guarded.

### 8.6 Notes

`Notes` contains informational, non-blocking module notes.

Tilde MUST NOT execute `Notes` content.

`Notes` content MUST NOT affect commit-anchor advancement.

## 9. Code Blocks

Tilde uses fenced shell code blocks in module README files.

No new declarative patch language is introduced.

Executable code blocks MUST be idempotent or guarded.

Tilde does not keep per-block marker state.

A block may run more than once. If a block performs a one-time effect, the block itself must test the intended live effect.

Example:

```bash
if [[ -f ~/.zsh_history && ! -f ~/.local/share/zsh/history ]]; then
	mkdir -p ~/.local/share/zsh
	mv ~/.zsh_history ~/.local/share/zsh/history
fi
```

If an effect cannot be safely detected from live target facts, the operation MUST NOT be automated silently. It must be represented as a prerequisite, note, or explicit proposal-first operator action.

## 10. Packages

Package declarations do not require persistent state.

The package manager is the source of truth for package presence.

Package operations MUST be idempotent or safely repeatable.

Examples:

```text
brew install foo
apt-get install foo
gem install foo
uv tool install foo
```

A package operation that requires privilege or external input returns `deferred`.

Package refresh and upgrade operations are not commit-anchor semantics. They MUST NOT advance or rewrite `applied` anchors by themselves.

### 10.1 Ephemeral Package Inventory

Apply may build an ephemeral installed package inventory to reduce unnecessary package operations.

During apply, install operations check package presence before invoking the package manager when the package type has a
bounded local presence check.

The inventory is:

- grouped by package manager,
- collected with one cheap list command per manager,
- kept in memory only,
- never persisted,
- used only to shrink install queues,
- not used as durable state.

Example inventory commands:

```text
brew formula : brew list --formula -1
brew cask    : brew list --cask -1
deb/dpkg     : dpkg-query -W -f='${binary:Package}\n'
gem          : gem list --no-versions
npm global   : npm list -g --depth=0 --json
flatpak      : flatpak list --app --columns=application
scoop        : scoop list
uv tools     : uv tool list
```

Presence checks MUST NOT require privilege. For Debian packages, use `dpkg-query`; do not use `sudo` merely to check whether a package is installed.

If inventory collection fails, Tilde MUST NOT treat the failure as proof that packages are missing. It may fall back to idempotent install or report the package manager as unavailable/deferred.

Where supported, install should be batched:

```bash
brew install git tmux zoxide
brew install --cask google-chrome dropbox
sudo -n apt-get install -y git curl build-essential
gem install rubocop rake
```

The basic package declaration means package present. Version constraints, provider packages, package origin, and executable availability are outside the first-level presence check unless explicitly specified.

### 10.2 Package Removal

Removed package declarations do not trigger automatic uninstall by default.

A removed package declaration is a cleanup candidate and MAY be reported.

Default behavior:

```text
removed package declaration -> report/propose only
```

Uninstall requires:

- explicit package-removal policy,
- proposal-first confirmation,
- and a successful package-manager operation.

This conservative rule applies even when the package existed in the last applied desired manifest. Installed package state is shared with the user, the system, other modules, and other tools.

## 11. Managedness Proof

Tilde MUST NOT perform destructive cleanup unless managedness is proven.

The rule is:

```text
no proof -> no destructive mutation
```

### 11.1 Links

A link target is managed when:

- the target is a symlink, and
- the symlink resolves to a current desired source, or
- the symlink resolves to an old desired source derived from the last applied commit anchors.

Missing links may be created. Correct links are `unchanged`. Wrong or dangling managed links may be replaced or proposed for replacement. Regular files or directories at the target are `conflict` unless an explicit backup strategy is active.

### 11.2 Spans

A span is managed when it is enclosed by a well-formed Tilde marker pair with a matching span ID.

Example:

```sh
# >>> tilde:local-bin
export PATH="$HOME/.local/bin:$PATH"
# <<< tilde:local-bin
```

Malformed marker pairs, duplicate IDs, and binary files are conflicts.

Tilde MUST NOT edit content outside a managed span.

### 11.3 Lines

A managed line action is based on exact line content.

`line ensure` may add an exact line if missing. `line remove` may remove the exact line when requested.

Line actions MUST NOT infer ownership of surrounding file content.

### 11.4 Copies

Copy managedness is conservative.

A copied file is not considered safely managed merely because it resembles a source file.

Copy cleanup requires explicit proof such as:

- a managed marker,
- a known checksum sidecar,
- explicit adoption metadata,
- or another policy-defined ownership proof.

Without proof, removed copy declarations are reported but not automatically removed.

### 11.5 Packages

Package managedness is weak because package-manager state is global.

A package that appears in an old desired manifest is not automatically considered safe to uninstall.

Package removal follows the package removal policy in this specification.

## 12. File Patching Helpers

File patching is performed with small idempotent helper commands under the Tilde `bin/` directory.

Recommended helpers:

```text
line
span
```

The helper names are intended for the Tilde skill command environment. Implementations should avoid exposing ambiguous generic helper names outside the intended Tilde runtime PATH.

Privileged helper calls use the same plain command names with `sudo`, such as `sudo line ...` and `sudo span ...`.

### 12.1 `line`

Interface:

```text
line ensure FILE LINE
line remove FILE LINE
```

Semantics:

```text
ensure:
  line exists      -> unchanged
  line missing     -> append, changed

remove:
  line exists      -> remove, removed
  line missing     -> unchanged or skipped
```

Example:

```bash
line ensure ~/.gitignore_global '.DS_Store'
line ensure ~/.profile 'export EDITOR=vim'
```

### 12.2 `span`

Interface:

```text
span ensure FILE ID
span remove FILE ID
```

Example:

```bash
span ensure ~/.zshrc local-bin <<'EOF_BLOCK'
export PATH="$HOME/.local/bin:$PATH"
EOF_BLOCK
```

Default marker format:

```sh
# >>> tilde:local-bin
export PATH="$HOME/.local/bin:$PATH"
# <<< tilde:local-bin
```

Semantics:

```text
span missing        -> append, changed
span identical      -> unchanged
span exists changed -> replace, changed
span malformed      -> conflict
multiple same IDs   -> conflict
binary file         -> conflict
```

A different comment prefix may be supported:

```bash
span ensure ~/.config/app.conf app-settings --comment ';' <<'EOF_BLOCK'
setting = true
EOF_BLOCK
```

which produces:

```ini
; >>> tilde:app-settings
setting = true
; <<< tilde:app-settings
```

### 12.3 Helper Output

Helpers MUST emit JSONL records to stdout.

Each stdout line MUST be one complete JSON object.

Helpers MUST NOT prefix JSONL records with text such as `tilde:`.

Human-readable diagnostics MUST be written to stderr.

Each helper invocation MUST emit at least one result record.

A result record MUST include:

- `schema`,
- `tool`,
- `op`,
- `status`,
- `target`.

When applicable, it SHOULD also include:

- `id`,
- `reason`,
- `line_sha256`,
- `changed`.

Example output stream:

```jsonl
{"schema":"tilde.helper/v1","tool":"span","op":"ensure","status":"changed","target":"~/.zshrc","id":"local-bin"}
{"schema":"tilde.helper/v1","tool":"line","op":"ensure","status":"unchanged","target":"~/.gitignore_global","line_sha256":"..."}
{"schema":"tilde.helper/v1","tool":"span","op":"ensure","status":"conflict","target":"~/.zshrc","id":"local-bin","reason":"malformed-marker"}
```

### 12.4 Helper Exit Codes

Helpers use these exit codes:

```text
0    success: changed / unchanged / skipped / removed
1    ordinary error / usage error / notok
2    conflict requiring user or agent decision
125  deferred privilege or external-input requirement
```

A helper that returns `conflict` MUST NOT modify the target.

## 13. Commit-Diff Cleanup

The `applied` commit anchors are used only to compute desired-state differences.

If old commits are available locally, Tilde may derive:

```text
old desired manifest at applied commits
new desired manifest at current commits
diff = old desired - new desired
```

This diff identifies cleanup candidates such as:

- links previously declared but no longer declared,
- links whose source or target changed,
- managed spans previously declared but removed,
- copies previously declared but removed,
- package declarations previously declared but removed.

Commit diff does not prove the live target is stale. It only identifies candidates.

Before changing anything, Tilde performs targeted live checks on candidate target paths.

If old commit anchors are missing or unavailable locally, ordinary apply MUST NOT fail. Tilde should report that cleanup diff is unavailable and continue with current desired reconciliation.

## 14. Targeted Live Checks

Normal apply/update/repair does not perform broad live scans.

For each current desired action or diff-derived cleanup candidate, Tilde checks only the relevant target path.

Examples:

- Is the target missing?
- Is it a symlink?
- Does it resolve to the expected source?
- Is it a Tilde-managed span?
- Is the file content already in the desired form?
- Is the target an unmanaged file or directory?

This is not a whole-home audit.

External drift, unrelated dangling links, and manual corruption outside current desired or diff-derived target paths belong to `doctor`.

## 15. Doctor

`doctor` diagnoses external drift and broader health problems.

Examples:

- manually broken links,
- dangling links not caused by repository changes,
- dirty repositories,
- missing repository bindings,
- malformed managed spans,
- stale Dropbox paths,
- unmanaged conflicts,
- untracked desired-looking files.

`doctor` may perform bounded live scans.

`doctor` MUST NOT execute module code blocks or mutate targets without a separate explicit proposal-first operation.

## 16. Repair

`repair` does not depend on module-level state.

In the stateless model:

```text
repair = apply current desired state again
```

Because all actions must be idempotent or guarded, rerunning repair is safe.

If a previous run failed, the commit anchors remain at the last fully successful commit pair. The next run still computes diff from those anchors to current HEAD.

## 17. Operator Workflows

One-off operator/agent workflows live outside the desired-state model. They are proposal-first and operator-approved.

An operator workflow SHOULD include:

- intent,
- preflight checks,
- compatibility checks against current desired modules,
- proposed actions,
- execution,
- verification,
- final compatibility checks.

Tilde may assist with existing primitives such as planning, doctor diagnostics, targeted checks, remote execution, and
helper commands.

Optional operator notes or temporary artifacts may be kept outside the desired-state model.

## 18. Failure Semantics

If a run fails or is deferred:

- do not advance `applied` anchors,
- do not record module-level partial success,
- do not treat attempted actions as converged,
- show the failure in command output,
- allow the next run to retry idempotently.

If `state.yml` is missing or has no `applied` section, Tilde treats the host as fresh:

- generate the current desired manifest,
- apply idempotently,
- skip commit-diff cleanup because no old anchor exists.

Fresh hosts run only declared desired-state actions automatically.

## 19. Remote Hosts

For remote deployment, `state.yml` and `applied` anchors live on the target host.

Controller-side paths MUST NOT be written as target bindings.

For an `ssh:<host>` target, the controller's `~/.local/state/tilde/state.yml` MUST NOT be used to discover or infer the
target host's repository bindings, applied anchors, level, platform, bootstrap state, or desired-state status. That file
belongs only to the controller host.

A controller may inspect or mirror remote status, but the target host's own state file is authoritative for that host:

```text
~/.local/state/tilde/state.yml
```

The host-local lock is also target-local.

### 19.1 Agent Remote-Work Pattern

Agents delivering remote work MUST use `tilde ssh HOST` for script delivery.
This guarantees the Tilde runtime and sudo intercept environment are active on
the target.

Agent-orchestrated remote workflows that generate plan files and apply them MUST deliver the full workflow as a single
piped script body. Planning and apply MUST both run on the target host. Platform detection, package inventory,
repository bindings, and live checks come from the target host.

Generating a plan on the controller for a remote host is invalid.

Reading controller deployment state before a remote workflow is also invalid. The first target-state read for
`ssh:<host>` work MUST be delivered to the target:

```text
tilde ssh HOST << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

```text
tilde ssh HOST << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

tilde plan --mode refresh --repo ~/Dropbox/home --host HOST --format json > "$tmpdir/public.json"
tilde plan --mode refresh --repo ~/Dropbox/home- --host HOST --format json > "$tmpdir/private.json"
tilde apply --plan "$tmpdir/public.json" --plan "$tmpdir/private.json"
SCRIPT
```

Repository paths in remote scripts are the target host's configured bindings. Public-only targets omit the private plan.

Single-command remote checks still use the same transport:

```text
tilde ssh HOST << 'SCRIPT'
tilde doctor
SCRIPT
```

## 20. Security and Proposal-First Behavior

Tilde must propose before:

- replacing unmanaged files,
- removing stale links or managed spans,
- backing up conflicting paths,
- uninstalling packages,
- running non-idempotent or unclear code,
- requiring privileges,
- performing remote mutations,
- running one-off operator workflows.

Helper commands MUST fail closed on malformed markers, ambiguous targets, binary files, and unmanaged conflicts.

## 21. State Recovery

If the persistent state file is missing or malformed, Tilde recovers repository bindings from explicit command
arguments, repository frontmatter, and bounded target discovery. A successful run writes `state.yml` with the recovered
bindings and fully converged anchors.

## 22. Summary

The model is:

```text
Persistent correctness state:
  state.yml only

Runtime coordination:
  host-local lock

Persistent state contains:
  repository bindings
  last fully applied commit anchors

Normal apply:
  current committed desired manifest
  ephemeral package inventory
  targeted live checks
  idempotent actions
  no broad scan

Cleanup:
  commit-diff candidates
  targeted verification
  managedness proof
  proposal-first destructive mutation

Module sections:
  Prerequisites
  Install
  Post Install
  Configure
  Update
  Notes

Code blocks:
  fenced shell
  idempotent or guarded
  helper commands for file patching
  pure JSONL helper output

Operator workflows:
  operator/agent workflow
  proposal-first
  not desired-state content
```

The central invariant is:

```text
Runtime state may help find the last fully converged commit pair.
Current desired state and targeted live facts decide current work.
```
