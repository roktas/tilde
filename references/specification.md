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

When a successful apply call contains only one repository role, the state write preserves existing bindings for omitted
roles. It preserves omitted role anchors only when the existing anchor metadata has the same level and platform as the
current successful apply. This keeps separately applied public/private plans from erasing each other while avoiding
claiming convergence for a role that was last applied under a different target identity.

### 3.2 Locking and Atomic Writes

Tilde MUST acquire a host-local lock before mutating targets or writing `state.yml`.

Recommended lock path:

```text
~/.local/state/tilde/lock
```

The lock is runtime coordination, not desired-state memory.

If a lock cannot be acquired because another Tilde process is active, Tilde MUST return a clear lock-busy or `deferred` result and MUST NOT mutate targets.

Agents MUST NOT remove the lock file merely because a command timed out or because the path exists. With process-held
locks such as `flock`, deleting the pathname does not prove the owning process has stopped and may allow a second run to
start while the first run is still active. Lock cleanup requires bounded read-only process inspection and explicit
operator approval when the owning process cannot be proven absent.

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
- directories,
- copies,
- seeds,
- resets,
- package declarations,
- helper-based file patches,
- executable fenced blocks,
- prerequisite checks,
- stale cleanup candidates derived from commit diffs.

## 7. Command Matrix

Tilde has three command surfaces:

- Prompt commands are user/agent workflows written with a prompt marker such as `/tilde COMMAND ...`.
- Runtime routes are direct `bin/tilde` helper commands.
- Implementation routes are runtime primitives used inside an agent workflow.

Prompt markers such as `/tilde` and `$tilde` are not shell commands. Implementations MUST NOT execute them in a
terminal.

Before executing a controller-side runtime route, agents MUST resolve the Tilde runtime entrypoint. The preferred
entrypoint is the loaded skill directory's `bin/tilde`. If that path is not available, the fallback entrypoint is:

```text
~/.agents/skills/tilde/bin/tilde
```

Examples write the resolved entrypoint as `"$TILDE"`:

```sh
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" help
"$TILDE" ssh spinoza
```

Agents MUST NOT rely on bare `tilde` being on the controller `PATH`. If a controller-side `tilde` command returns
`command not found`, the agent MUST NOT search the filesystem for another command. It MUST retry through the resolved
runtime entrypoint.

Bare `tilde` is valid only where Tilde has already made its runtime `bin/` directory PATH-visible, including inside a
remote script body delivered by Tilde SSH transport.

Prompt commands such as `deploy`, `update`, and `repair` are interpreted by the loaded Tilde skill. They do not have a
direct runtime route.

Host-aware prompt commands accept these target forms:

```text
no target   current host, also called localhost
host        remote host shorthand for ssh:host, except when it names the current host
ssh:host    explicit remote host target
GROUP       bare all-caps host group defined by the active home policy
```

If a bare host token equals the current host name, such as `hostname -s`, agents MUST treat it as the current host and
run the local workflow. Explicit `ssh:host` is required to force SSH transport to that host, including self-SSH.

The host-aware prompt commands are:

```text
deploy
update
repair
align
status
doctor
```

Tilde intentionally has no public `create`, `init`, `adopt`, `clean`, `organize`, or `upgrade` prompt commands.
Unmatured one-off home-management work stays as ordinary proposal-first agent work outside the core command surface.

Bare all-caps targets such as `ALL`, `HOME`, and `WORK` are home-policy host groups, not hostnames. Agents MUST expand a
host group from the active `~/AGENTS.md` policy before running remote work. Group expansion applies only to unprefixed
target tokens; `ssh:host` is always an explicit host target. If the policy does not define the requested group, agents
MUST ask the user for the host list. For explicitly requested configured groups, agents MUST report the expanded host
list and continue; the prompt itself is consent to run the requested workflow. Agents MUST ask only when the group is
undefined, ambiguous, unexpectedly expands outside active policy, or a later step requires separate explicit
confirmation. Each expanded host is a separate target workflow with separate status, plan, apply, and closeout
reporting.

When traversing a host group, agents MUST perform a bounded noninteractive reachability check before each host workflow:

```text
host=spinoza
"$TILDE" ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" << 'SCRIPT'
printf 'ok\n'
SCRIPT
```

If the reachability check fails, agents MUST mark that host `skipped`, report the reason briefly, and continue with the
remaining hosts. An unreachable host inside a group MUST NOT fail reachable hosts. If every expanded host is
unreachable, the command result is `deferred`.

Reachability checks for Tilde workflows MUST use Tilde SSH transport. Agents MUST NOT use raw `ssh`, `sh -c`, or
`bash -lc` for these probes.

Direct runtime commands such as `help`, `doctor`, `handoff`, and `status` may be run through `bin/tilde`. For remote
targets, the command must run on the target host through the Tilde SSH transport.

`align` is both a local runtime command and a prompt workflow. Remote align is agent-orchestrated. Agents MUST NOT run
`tilde align --format json` on a remote target; `align` has no `--format` option. Remote align uses target-local
`plan --mode align --format json` files and `tilde apply`.

Implementation routes such as `ssh`, `plan`, `apply`, `sudo`, `boot`, `checkout`, `preflight`, and `smoke` are stable
runtime primitives. They are not user-facing prompt commands.

Tilde planning modes execute module sections according to this matrix.

```text
prompt command -> plan mode
  deploy  -> apply
  update  -> refresh
  update --managed -> refresh --managed
  update --greedy -> refresh --greedy
  update with missing state.yml or no applied anchors -> repair
  repair  -> repair
  align   -> align
```

The prompt command is `update`; the ordinary planning mode is `refresh`. Implementations MUST NOT invent a
`--mode update`. If target status shows missing `state.yml` or no `applied` anchors, an update workflow MUST recover
state with `repair` mode for that run because state recovery should recreate fully converged bindings and anchors
without running `Update` sections. Missing state is not proof that the host was never deployed; agents SHOULD describe
this as state recovery unless bounded evidence proves otherwise.

Refresh mode reconciles current desired-state declarations. A repository change that adds a package, link, copy, seed,
reset, or other install-time declaration is reconciled by ordinary update. The default refresh updates system package
managers such as Homebrew and apt. `--managed` also refreshes managed non-system package declarations such as gem, npm,
egg, skill, and declared flatpak packages. `--greedy` is valid only with refresh mode, implies `--managed`, and appends
broad package-manager upgrade actions after normal update actions. Repair remains available when the intent is
desired-state convergence without package refresh actions, broad package upgrade actions, or `Update` sections.

Agents that materialize plan JSON files MUST write them under a per-run temporary directory and remove that directory at
workflow exit. Fixed plan paths under shared temp locations, such as `/tmp/opencode/HOST-public.json`, are invalid for
agent workflows because they leak state across runs and hosts.

Example:

```text
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

"$TILDE" plan --mode refresh --repo ~/Dropbox/home --host newton --format json > "$tmpdir/public.json"
"$TILDE" apply --plan "$tmpdir/public.json"
```

Tilde-generated refresh plans are convergent update plans. After a successful update workflow, final status MUST show
the current repository HEAD recorded under `applied` anchors. Agents MUST NOT report update convergence from target
repository HEAD alone; they MUST verify the target-local state file after apply.

```text
apply / install:
  Prerequisites
  package install actions
  Install
  Post Install, only if the install phase changed in the current run
  directories, links, copies, seeds, and resets
  Configure

refresh / update:
  package refresh actions
  Prerequisites
  package install actions
  Install
  Post Install, only if the install phase changed in the current run
  directories, links, copies, seeds, and resets
  Update
  Configure

refresh / update with --greedy:
  refresh/update actions
  broad package-manager upgrade actions after refresh/update actions

repair:
  Prerequisites
  package install actions
  Install
  Post Install, only if the install phase changed in the current run
  directories, links, copies, seeds, and resets
  Configure

align:
  directories, links, copies, seeds, and resets only
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

`handoff` prints one shell-neutral privilege-preparation command line for the local or selected remote host and attempts
to copy it to the controller clipboard using a platform-appropriate clipboard command. The command must be suitable for
direct paste into bash, zsh, or fish. When the local or target runtime supports it, `handoff` SHOULD print the short
runtime helper form, such as `~/.agents/skills/tilde/bin/sudo --handoff` or
`ssh -t HOST '~/.agents/skills/tilde/bin/sudo --handoff'`. Agents MUST run `handoff` on the controller, not through
Tilde SSH transport, and MUST present the printed `Handoff command:` line exactly. Agents MUST NOT split it into
environment assignments and a separate command.

For remote first-time bootstrap, the printed command MUST NOT assume that the target Tilde runtime already exists. It
SHOULD use the target runtime when present and otherwise perform the minimal validated sudoers bootstrap needed for
subsequent Tilde sudo operations.

## 8. Module Sections

Module README frontmatter may declare module-level properties and platform-scoped desired state.

Supported desired-state keys are:

- `links`: symlink targets,
- `directories`: directories that must exist,
- `copies`: conservative file copies where drift is a conflict,
- `seeds`: initial file copies where existing real targets are local state,
- `resets`: repository-authoritative file copies,
- `packages`: package declarations.

Package declarations are strings in either prefixed or unprefixed form. Prefixed values use `type:name`, such as
`deb:curl`, `cask:google-chrome`, `flatpak:org.gimp.GIMP`, or `skill:github.com/owner/repo`. Unprefixed values resolve
to the platform default package manager: `brew` on Linux and macOS, and `scoop` on Windows. Debian packages MUST use the
explicit `deb:` prefix; agents MUST NOT treat an unprefixed Linux package as a Debian package merely because the target
uses apt.

`level` is a module-level property. Prefer declaring it at the top level of the module frontmatter:

```yaml
level: extra
all:
  packages:
    - foo
    - deb:curl
```

When top-level `level` is absent, `all.level` has the same meaning.

`phase` is a module-level property with values `normal` and `early`. The default is `normal`. Early actions are applied
before normal actions across all plans in the same apply run, while preserving role and action order inside each phase.
Use `phase: early` only for small prerequisite-style modules that unblock later desired-state actions, such as a private
Linux sudoers baseline. Early modules still follow the normal section order and must remain idempotent.

Link sources are repository-relative by default. A link source that starts with `~/` or `/` is a target-home source and
MUST stay inside the target home. Use target-home sources for managed links between home-managed live paths, such as
Dropbox-backed shared state directories and XDG entrypoints. When both source and target are inside `~/Dropbox`, Tilde
MUST write the symlink value relative to the target directory rather than using an absolute host path.

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

Platform-scoped section groups are supported at level 2 with ordinary module sections nested at level 3:

```text
## Linux
### Install

## MacOS
### Configure
```

Supported platform group headings are `All`, `All Platforms`, `Linux`, `MacOS`, `Darwin`, and `Windows`. During
planning, Tilde selects top-level special sections plus sections nested under `All`/`All Platforms` and the target
platform heading. Platform-scoped sections make a module applicable for that platform even when the README frontmatter
does not contain a matching platform key. Do not add dummy `linux:`, `macos:`, directories, links, packages, or
platform `level` entries solely to make a platform-scoped section run.

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

If package install actions or Install create or install something in the current run, they return `ok` or `changed` as
appropriate. A changed install phase enables `Post Install` for the same module in that run.

### 8.3 Post Install

`Post Install` contains install-event hooks that run only when the module's install phase changed something in the
current run. The install phase includes declared package installs and the module's `Install` section.

If the install phase is unchanged, `Post Install` is skipped.

`Post Install` is an optimization and event hook. It is not a correctness layer.

Required final configuration MUST live in `Configure`, not only in `Post Install`.

`Post Install` blocks SHOULD still be guarded or idempotent because later failures may prevent commit-anchor advancement and cause the run to be retried.

### 8.4 Configure

`Configure` contains idempotent configuration and reconciliation steps.

`Configure` is the correctness layer for desired configuration.

It runs after declared directories, links, copies, seeds, and resets are materialized. In update mode, it also runs
after `Update`.

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

Package declaration prefixes select the package manager. If no prefix is present, Tilde uses the platform default
package type: `brew` on Linux and macOS, and `scoop` on Windows. Agents MUST preserve this meaning when reviewing or
editing modules. On Linux, do not check `dpkg` or apt state for an unprefixed package declaration; check Homebrew
formula state. Use `deb:name` only for packages that must be installed through apt/dpkg.

Package operations MUST be idempotent or safely repeatable.

Examples:

```text
brew install foo
apt-get install foo
gem install foo
uv tool install foo
```

A package operation that requires privilege or external input returns `deferred`.

Package metadata refresh that reports incomplete indexes, signature verification failures, missing repository keys, or
failed source fetches returns `deferred` even if the package manager exits successfully.

Package refresh and upgrade operations are not commit-anchor semantics by themselves. A full Tilde-generated
refresh/update plan MAY advance `applied` anchors only because it also reconciles current desired state and every
required action succeeds.

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

Missing links may be created. Correct links are `unchanged`. Links removed from current desired state may be removed
only when the live target is a symlink and its link value exactly matches an old desired source derived from the last
applied commit anchors. Wrong or dangling managed links may be replaced or proposed for replacement. Regular files or
directories at the target are `conflict` unless an explicit backup strategy is active.

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

### 11.4 File Materialization

Tilde supports three file materialization intents: `copies`, `seeds`, and `resets`.

`copies` is conservative. Missing targets are copied from the repository. Existing targets that differ from the
repository source are `conflict`. A copied file is not considered safely managed merely because it resembles a source
file.

`seeds` creates an initial independent file or directory. If the target is missing, Tilde copies the repository source.
If the target is a real file or directory, Tilde leaves it unchanged without comparing content. This is for files that
applications legitimately mutate after first install. If the target is a matching symlink, Tilde replaces that symlink
with an independent copy. A differing symlink is `conflict`.

`resets` treats the repository source as authoritative. Missing targets, symlink targets, and drifted real targets are
replaced by a fresh copy of the repository source without an additional conflict prompt. Use `resets` only for files
whose local drift should be repaired by every apply, repair, or align run.

Materialization cleanup requires explicit proof such as:

- a managed marker,
- a known checksum sidecar,
- explicit adoption metadata,
- or another policy-defined ownership proof.

Without proof, removed copy, seed, or reset declarations are reported but not automatically removed.

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
- file materializations previously declared but removed,
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

Repair differs from update by skipping package refresh actions, broad package upgrade actions, and `Update` sections.

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

The `apply` runtime route MUST emit its structured JSON result before exit. If `completed` is false, or any required
action result is `deferred`, `conflict`, or `notok`, `apply` MUST exit non-zero after writing that JSON. Agents MUST
inspect the action results instead of treating a printed JSON document or `completed: true` alone as full success.

If `state.yml` is missing or has no `applied` section, Tilde uses fresh-run semantics:

- generate the current desired manifest,
- apply idempotently,
- skip commit-diff cleanup because no old anchor exists.

Fresh-run semantics are not proof that the host was never deployed. They only mean no fully converged anchor is
available for this run. Hosts without anchors run only declared desired-state actions automatically.

## 19. Remote Hosts

For remote deployment, `state.yml` and `applied` anchors live on the target host.

Controller-side paths MUST NOT be written as target bindings.

For a remote target, the controller's `~/.local/state/tilde/state.yml` MUST NOT be used to discover or infer the target
host's repository bindings, applied anchors, level, platform, bootstrap state, or desired-state status. That file belongs
only to the controller host.

A controller may inspect or mirror remote status, but the target host's own state file is authoritative for that host:

```text
~/.local/state/tilde/state.yml
```

The host-local lock is also target-local.

### 19.1 Agent Remote-Work Pattern

Agents delivering remote work MUST use Tilde SSH transport for script delivery.
This guarantees the Tilde runtime and sudo intercept environment are active on
the target.

Tilde SSH transport loads non-secret `~/.config/environment.d/*.conf` values before the remote script body. It does not
load shell credentials.

The remote freshness preflight is the first remote workflow step. Before reading target state, generating plans, applying
plans, or deciding state-recovery mode, agents MUST perform it with the deterministic controller-side route:

```text
"$TILDE" preflight remote HOST --format json
```

The route MUST NOT require the target `~/.agents/skills/tilde` runtime to exist or be current. It uses Tilde SSH
transport without injecting a target runtime and returns one JSON document that classifies reachability, bootstrap
baseline, repository backend, target runtime, Dropbox runtime, target state, repository bindings, sudo state, controller
runtime commit, and next steps.

Agents MUST use `bootstrap.needed` and `next` from this JSON for the initial bootstrap decision. They MUST NOT infer
bootstrap need from free-form logs, guessed package state, or controller-side state. The bootstrap baseline is
intentionally small: Homebrew, `curl`, `git`, and `ruby` must be usable on the target.

The `sudo.noninteractive` field reports the broad `sudo -n true` probe. It is not a general handoff trigger for
already deployed Linux hosts, because a host may intentionally allow only package-management commands without a
password. The `sudo.apt` field reports whether the exact noninteractive apt form used by Tilde package actions can run.
For ordinary `update` and `repair` package work, agents MUST proceed when `sudo.apt=true` and MUST request handoff only
when preflight `next` asks for it or a real apply step returns a sudo deferral.

Remote freshness preflight checks:

- the target `~/.agents/skills/tilde` runtime commit matches the controller-side loaded Tilde runtime commit,
- on Dropbox-backed interactive hosts, whether the durable runtime symlink can be used,
- Git-backed target desired-state checkouts match the controller-side public/private repositories selected for the run,
- target checkouts are clean before any controller bundle is applied,
- Dropbox-backed target repositories are not replaced with controller bundles unless explicitly requested.

For Dropbox-backed interactive hosts, the durable runtime shape is:

```text
~/.agents/skills/tilde -> ~/Dropbox/tilde
```

A clean clone at `~/.agents/skills/tilde` is only a provisional bootstrap or freshness runtime. Agents MAY convert it
with:

```text
"$TILDE" checkout runtime-link --host HOST --source '~/Dropbox/tilde' --target '~/.agents/skills/tilde' --expected COMMIT
```

only when preflight shows the Dropbox runtime exists, is a Git checkout, has executable `bin/tilde`, is clean, and
matches the controller runtime commit. If the Dropbox checkout is absent, dirty, missing `bin/tilde`, or stale, agents
MUST defer symlink conversion instead of replacing it with a controller bundle.

For mutating remote prompt workflows such as `deploy`, `update`, `repair`, and remote `align`, a stale
Git-backed target runtime or desired-state checkout SHOULD be refreshed from the controller checkout with the
`checkout remote` implementation route before target `tilde status`, `tilde plan`, or `tilde apply` is run. If a stale
runtime or checkout cannot be refreshed safely because it is dirty, missing, not a Git checkout, or ambiguous, the run
MUST return `deferred`.

If a clean target runtime cannot fast-forward because its history differs from the controller runtime, agents MAY use
`checkout remote --replace-clean` to replace that clean runtime checkout. Agents MUST NOT use `--replace-clean` for
public/private desired-state checkouts unless the operator has explicitly approved replacing that clean checkout.

Agents MUST NOT patch, edit, or `sed` target runtime or desired-state checkouts as part of deploy, update, repair, or
align and then continue as if that target-side patch completed the workflow. The correct response is to
capture the exact target diff, report it for source-repository review, and leave the workflow `deferred` unless the
source repository is fixed and refreshed through normal checkout freshness routes.

Temporary target edits are allowed only as a separate explicitly approved recovery or debugging operation. Accepted
changes MUST be ported to the controller source repository, committed there, and delivered back to the target through
normal checkout freshness routes before retrying the original workflow. Stashing, discarding, or otherwise cleaning
target checkout changes is also a separate recovery step that requires explicit operator approval.

The `checkout remote` route MUST be called with the full controller-to-target mapping:

```text
"$TILDE" checkout remote --host HOST --repo CONTROLLER_REPO --target TARGET_REPO
```

For target runtime freshness, the controller repository is the loaded skill root and the target is
`~/.agents/skills/tilde`:

```text
controller_runtime=${TILDE%/bin/tilde}
"$TILDE" checkout remote --host spinoza --repo "$controller_runtime" --target '~/.agents/skills/tilde'
```

For Git-backed desired-state checkout freshness, the controller repository is the selected data repository and the
target is the target host's bound checkout:

```text
"$TILDE" checkout remote --host vps --repo ~/Dropbox/home --target '~/.local/src/home'
```

Agents MUST NOT call `checkout remote` with only `--host`. The route cannot infer repository bindings from a host name.
Agents MUST quote target paths that start with `~` so the controller shell does not expand them before delivery to the
remote host.

If the preflight JSON reports a temporary `/etc/sudoers.d/tilde` rule, agents SHOULD remove it after the
privilege-dependent workflow no longer needs it:

```text
"$TILDE" sudo cleanup --host HOST
```

The cleanup is complete only when the following preflight no longer reports the rule.

For read-only remote workflows such as `status` and `doctor`, a stale target runtime is reported as a stale-runtime
condition. It is not permission to mutate the remote host.

A target status output that references state paths outside this specification, such as
`~/.local/state/tilde/config.yml` or `~/.local/state/tilde/hosts/HOST/state.md`, indicates a stale target runtime.
Agents MUST stop and refresh or report the stale runtime before any state-recovery plan. State writes outside the
`state.yml` model MUST NOT be reported as successful recovery under this specification.

Agent-orchestrated remote workflows that generate plan files and apply them MUST deliver the full workflow as a single
piped script body. Planning and apply MUST both run on the target host. Platform detection, package inventory,
repository bindings, and live checks come from the target host.

Generating a plan on the controller for a remote host is invalid.

After the target runtime is known current, machine-readable target status is the preferred source for repository
bindings:

```text
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format json
SCRIPT
```

Use the returned `state.public` and `state.private` paths exactly when generating target-local plans. Do not guess
`~/Dropbox/home`, `~/Dropbox/home-`, `~/.local/src/home`, or `~/.local/src/home-` when status, explicit user arguments,
or active home policy can supply the target binding.

For Git-backed targets whose status binds repositories outside Dropbox, controller-side `~/Dropbox/...` source paths are
not target paths. Agents MUST NOT create target-side `~/Dropbox` for repository binding, cleanup, shared app state, or
convenience paths unless active target policy explicitly says that host has Dropbox-backed storage.

When a remote workflow needs repository bindings in a target-side script, agents MUST bind them from target status JSON
before planning. Agents MUST NOT retype host-convention paths in `tilde plan --repo ...` commands:

```text
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
status_json=$tmpdir/status.json

tilde status --format json > "$status_json"
public=$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); print data.dig("state", "public").to_s' "$status_json")
private=$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); print data.dig("state", "private").to_s' "$status_json")
if [ -z "$public" ]; then
  printf '%s\n' 'STATUS_FAILED: missing state.public' >&2
  exit 1
fi
SCRIPT
```

Reading controller deployment state before a remote workflow is also invalid. After remote freshness preflight, the
first target-state read for remote work MUST be delivered to the target:

```text
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

```text
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
status_json=$tmpdir/status.json
mode=refresh
# Use mode=repair when target status reports missing state.yml or no applied anchors.

tilde status --format json > "$status_json"
public=$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); print data.dig("state", "public").to_s' "$status_json")
private=$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); print data.dig("state", "private").to_s' "$status_json")
if [ -z "$public" ]; then
  printf '%s\n' 'STATUS_FAILED: missing state.public' >&2
  exit 1
fi

tilde plan --mode "$mode" --repo "$public" --host spinoza --format json > "$tmpdir/public.json" || exit $?
if [ -n "$private" ]; then
  tilde plan --mode "$mode" --repo "$private" --host spinoza --format json > "$tmpdir/private.json" || exit $?
  tilde apply --plan "$tmpdir/public.json" --plan "$tmpdir/private.json"
else
  tilde apply --plan "$tmpdir/public.json"
fi
SCRIPT
```

Repository paths in remote scripts are the target host's configured bindings. Public-only targets omit the private plan.
Inside the remote script body, bare `tilde` is valid because the Tilde SSH transport has already set the target runtime
PATH.

Remote align uses the same target-local plan/apply shape with align mode:

```text
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
status_json=$tmpdir/status.json
mode=align

tilde status --format json > "$status_json"
public=$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); print data.dig("state", "public").to_s' "$status_json")
private=$(ruby -rjson -e 'data = JSON.parse(File.read(ARGV[0])); print data.dig("state", "private").to_s' "$status_json")
if [ -z "$public" ]; then
  printf '%s\n' 'STATUS_FAILED: missing state.public' >&2
  exit 1
fi

tilde plan --mode "$mode" --repo "$public" --host spinoza --format json > "$tmpdir/public.json" || exit $?
if [ -n "$private" ]; then
  tilde plan --mode "$mode" --repo "$private" --host spinoza --format json > "$tmpdir/private.json" || exit $?
  tilde apply --plan "$tmpdir/public.json" --plan "$tmpdir/private.json"
else
  tilde apply --plan "$tmpdir/public.json"
fi
SCRIPT
```

Agents MUST NOT redirect remote Tilde diagnostics to `/dev/null` for status, doctor, checkout, plan, apply, align, or
verification steps. A non-zero remote exit status is failed, deferred, or conflicted work even when stdout is empty. A
later successful status read does not convert an earlier failed checkout, plan, apply, or align step into success.

Remote scripts MUST be `sh`-compatible by default. Agents MUST use the plain `"$TILDE" ssh HOST << 'SCRIPT'` form for
ordinary status, plan, apply, and verification work. Agents MUST NOT pass `-- bash` for macOS targets or for scripts
that can run under `sh`. Passing an interpreter after `--` is reserved for a verified non-macOS target and a script that
truly needs syntax absent from `sh`; the transport MUST run that interpreter as the remote script reader.

In the default remote form, `sh`-compatible means POSIX `sh`, not "Bash without a Bash shebang." Agents MUST NOT use
the Bash skill prelude in these remote scripts. Agents MUST avoid common Bashisms:

| Bashism | POSIX `sh` form |
| --- | --- |
| `set -o pipefail` | avoid critical pipelines; check each command separately |
| `[[ -n $x ]]` | `[ -n "$x" ]` |
| `[[ $x =~ re ]]` | `case $x in pattern) ... ;; esac` |
| `arr=(a b)` and `${arr[@]}` | newline-separated strings, positional parameters, or repeated commands |
| `source file` | `. file` |
| `function name { ...; }` | `name() { ...; }` |
| `local x=...`, `declare`, `mapfile`, `readarray`, `select` | simple variables and explicit loops |
| `< <(cmd)` and `<<< "$text"` | temp files, pipes, or here-documents |
| `{foo,bar}` brace expansion | spell out the words |
| `$'...\n...'` strings | `printf '%s\n' ...` |

`dash` is a common `/bin/sh`; scripts that only work in Bash are invalid in the plain remote form.

After a successful mutating remote apply, agents MUST perform a final cheap target-local status read before final
closeout:

```text
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

The final status read verifies target-local `state.yml`, target repository heads, and applied anchors without broad
discovery. It is not required for `dry-run`, `plan-only`, failed apply, or deferred apply.

Remote summaries MUST distinguish:

```text
target HEAD     the repository commit currently checked out on the target host
applied anchor  the commit recorded under applied in the target host state file
```

Do not call the target repository HEAD `local`; from the controller that word is ambiguous.

Single-command remote checks still use the same transport:

```text
"$TILDE" ssh spinoza << 'SCRIPT'
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

If apply returns a `conflict`, agents MUST stop after reporting the exact conflicted targets and MUST wait for an
explicit user response before replacing files, forcing links, copying repository versions over targets, or rerunning
apply. Consent is not implied by silence, by the existence of a conflict, or by the agent's own question. If resolving
one conflict reveals another conflict in a later apply, the later conflict requires a separate explicit response.
`resets` actions are not conflict resolution; they are explicit repository-authoritative desired state and may replace
their exact targets according to the module declaration.

When the user chooses repository replacement for a conflict, agents SHOULD preserve a backup when practical, remove only
the exact conflicting target, and rerun apply so the declarative action recreates it. Agents MUST NOT treat a replacement
choice as permission for broader cleanup. Broad cleanup, such as clearing an entire font directory after package-manager
file conflicts, requires a separate explicit approval that names the directory and effect.

## 21. State Recovery

If the persistent state file is missing or malformed, Tilde recovers repository bindings from explicit command
arguments, repository frontmatter, and bounded target discovery. A successful desired-state recovery run writes
`state.yml` with the recovered bindings and fully converged anchors. Package-only refresh or update-section-only plans
do not establish fully converged anchors. Missing state alone does not prove that the host was never deployed.

Home-policy cleanup hooks, such as Dropbox conflicted-copy cleanup after update, MUST remain bounded to the literal
paths named by active policy. A Dropbox path resolved through a symlink or platform-specific cloud-storage location is
not an additional cleanup root unless the active policy explicitly names it.

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
