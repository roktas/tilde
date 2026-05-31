# Tilde Spec

Tilde is a dotfiles and home provisioning repository operated by an agent. It can provision the current machine or a
remote machine reached over SSH. The durable behavior lives here; skills and helpers implement this spec.

## Terms

- **Module**: a root directory that represents one application or provisioning unit.
- **Misc module**: the normal `misc` module for small shared declarations that do not deserve a focused module. It has
  no bootstrap role. If `misc-` exists, it is an `extra` module.
- **Platform module**: `linux`, `macos`, or `windows`. It defines generic platform behavior such as package-manager
  policy or platform defaults.
- **Platform variant**: `linux-`, `macos-`, or `windows-`. The active variant runs immediately after the active platform
  module. The trailing dash has no global meaning; the module README defines the local semantics.
- **Host**: the short name derived from `hostname -f` by removing the trailing domain. For example, `kant.local` becomes
  `kant`.
- **Home**: the target user's home directory on the machine being managed. After deployment, Tilde's main user-facing
  surface is the home directory, not the repository checkout.
- **Home router**: the short Tilde-specific entrypoint linked to `~/AGENTS.md`. Its canonical template is
  `.agents/skills/tilde/assets/AGENTS.md`. Tilde deployment manages the link directly as a core link, independent of
  root modules. The router tells agents how to find this repository, how to find the private companion repository when
  present, and which guardrails apply when working from home.
- **Deployment**: applying Tilde's desired state to a local or remote host. Deployment is the user-facing operation that
  may include bootstrap, repository preparation, planning, applying links/copies/packages, and state update.
- **Provisioning**: the lower-level module operation performed during deployment: evaluating module frontmatter and
  README instructions, then installing packages and creating links or copies.
- **Managed surface**: files, directories, links, copies, packages, and deployment state that Tilde can explain from its
  active repository definitions.
- **Private companion repository**: optional sibling `tilde-` repository used for private modules, private policy, and
  preference-sensitive home behavior. It is a policy/source companion, not a separate command scope.
- **Proposal**: an agent-produced plan for a home-management action. A proposal describes intended reads, writes, moves,
  links, copies, or removals before any action is taken.
- **Deployment state**: runtime record for a host. Deployment state records module deployment results; home-management
  proposals are not written to deployment state.

## Model

- Each module describes how to install or configure one application or virtual provisioning unit.
- Module names usually match the common application name and default package name. Exceptions belong in the module
  `README.md`.
- A module directory contains `README.md` and any files used during provisioning. README frontmatter is optional.
- Root modules are direct child directories of the repository root. Dot directories, `.git`, and `.agents` are excluded.
- A root directory is a module only when it contains `README.md`.
- Provisioning decisions are made after host deployment state is loaded.
- On fresh or underprovisioned hosts, run `bin/bootstrap` explicitly before normal provisioning when
  baseline tools are missing. Bootstrap is state-free and idempotent.
- Deployment uses provisioning modes internally. User-facing commands may say `deploy`, while lower-level module
  execution may use `apply`, `refresh`, `repair`, or `upgrade`.
- Normal plans process the active platform module first, the active platform variant second, and all other active root
  modules alphabetically. Inactive platform modules and inactive platform variants are excluded.
- Root modules may be platform-gated by defining only platform keys such as `linux:`.
- Deployment state for a host is written under `.agents/state/hosts/HOST/tilde.md` in the repository copy where work is
  performed.

## Paths

- In tracked repository files, write home paths with `~`; do not write expanded home paths.
- Use repository-relative or module-relative paths for files inside this repository.
- Do not add machine-specific, user-specific, or local checkout-specific absolute filesystem paths to frontmatter,
  instructions, specs, notes, or scripts.

## Repository Layout

```text
.
  misc/
    README.md
  linux/
    README.md
  linux-/
    README.md
  macos/
    README.md
  git/
    README.md
    config
    ignore
    hooks/
    bin/
  .agents/
    specs/
      tilde.md
    state/
      hosts/
        HOST/
          tilde.md
```

`.agents/state/` is runtime state. Whether it is tracked is a repository-owner decision; this spec does not require it.

## Module README

A module `README.md` has optional YAML frontmatter and a Markdown body. Modules without explicit provisioning config may
omit frontmatter entirely. Missing `all` and platform keys are treated as empty maps.

Example:

````markdown
---
all:
  links:
    config: ~/.config/git/config
    ignore: ~/.config/git/ignore
    hooks/: ~/.config/git/hooks
    bin/: ~/.local/bin
  packages:
    - foo-bar
    - cask:foo-baz
    - deb:baz
    - npm:qux
    - gem:fred
    - egg:waldo
    - flatpak:org.foo.bar
    - github:user/project
  level: normal
  hosts:
    - hostname
macos:
  links:
    bin/: ~/.local/bin
windows: ~
---

# Foo

Foo is bla bla.

## Install

```bash
brew install foo-qux
```
````

### Frontmatter

Frontmatter is a two-level map. The first level contains platform scopes. The second level contains links, copies,
packages, level, and an optional host filter.

First-level keys:

- Valid scopes are `all`, `linux`, `macos`, and `windows`.
- For the active host, start with `all`, then shallow-merge the active platform scope when present.
- Map values such as `links` and `copies` are shallow-merged one level deep.
- List and scalar values such as `packages` and `level` are replaced by the platform value when present.
- Nested maps are not deep-merged.
- If a root module has no `all` key and only platform keys, the module is excluded unless the active platform key exists.
  This also prevents body sections from running on the wrong platform.
- A platform scope may be YAML null (`macos: ~`). This selects the module for that platform without adding platform
  frontmatter actions.

Second-level keys:

**`links`** maps module-relative sources to symlink targets. Sources normally live in the module directory. Sources may
use `../` for shared files elsewhere in the repository, but normalized sources must not escape the repository. A target
may be a string or a list of strings. Use a list when one source must be linked to multiple targets.

If the source key does not end in `/`, the source file or directory itself is symlinked to the target. If the source key
ends in `/`, the link uses fan-in semantics: each direct child of the source directory is linked into the target
directory with the same basename. For example, `bin/: ~/.local/bin` links `bin/foo` to `~/.local/bin/foo` and `bin/bar`
to `~/.local/bin/bar`.

If a link target already exists, the provisioning action replaces it with the module source after confirmation. This is
intentionally aggressive; preserve local target changes before provisioning.

**`copies`** maps module-relative sources to physical copy targets. Sources must not escape the repository. Missing
target parent directories are created. Directory sources are copied recursively. Existing targets are replaced after
confirmation. Copy targets removed from frontmatter are not removed unless the user explicitly asks for copy removal.

**`packages`** is a flat YAML list of `[package-type:]package-name` strings. Do not nest package types as mapping keys;
use `gemini-cli` or `brew:gemini-cli`, not `brew: [gemini-cli]`.

Valid package types are `brew`, `cask`, `deb`, `npm`, `gem`, `egg`, `flatpak`, `scoop`, and `github`.

When no package type is provided, Linux and macOS default to `brew`; Windows defaults to `scoop`. `deb` installs are
system-wide through `sudo`. Other package types are installed user-wide through their package managers. Prefer `bun` for
`npm` packages and `uv` for `egg` Python tools. `github` packages are installed from release assets, with executables
placed in `~/.local/bin`.

If `packages` is missing, the module is virtual and installs no packages. Add package names explicitly for modules that
install packages. `packages: []` is valid but usually unnecessary.

Package management defaults to installation only. Packages removed from frontmatter are not removed unless the user
explicitly asks for package removal.

`packages` is plan-time declaration only. The harness does not evaluate runtime conditions. If package installation
depends on runtime state, put a guarded command in a special README section such as `Install` or `Preinstall` instead.
If the condition is not met, the command may exit `0` as an intentional no-op.

GUI or desktop-host-dependent package installs also belong in guarded special-section commands, not in frontmatter
`packages`. Because SSH provisioning can target a desktop host without a GUI session, do not use `DISPLAY` or
`WAYLAND_DISPLAY` as the package-install guard. On Linux, prefer `systemctl get-default == graphical.target` for package
installs. Keep session checks such as `DISPLAY`, `WAYLAND_DISPLAY`, and `XDG_CURRENT_DESKTOP` for commands that truly
require an active GUI session, such as `gsettings`, MIME association, or launching GUI programs.

**`level`** is the provisioning scope level. Valid values are `minimal`, `normal`, and `extra`. The default is `normal`.
Plan selection uses threshold semantics: `minimal` includes only `minimal`; `normal` includes `minimal` and `normal`;
`extra` includes all three. Use `minimal` for the smallest useful base and `extra` for heavier optional or personal
tools.

**`hosts`** is an optional host filter. Entries match the short host name derived from `hostname -f`.

### Body

The README body is agent instruction text. Some headings are conventional special sections, documented under
Provisioning.

If a special section contains only `bash` fenced blocks and no other instruction text, the blocks are run in written
order after confirmation.

Special sections may contain lower-level headings such as `### GNOME`. These headings group literate instructions and
do not create new special-section semantics.

README bodies may use platform scopes: `## All Platforms`, `## Linux`, `## MacOS`, and `## Windows`. Inside such scopes,
write special sections one level lower, such as `### Install`. The active plan selects `All Platforms` and the active
platform only. Top-level sections such as `## Install` remain valid and are treated as all-platform sections. When a
top-level special section and a scoped special section share the same name, their bodies are concatenated in document
order.

The harness does not interpret a special `Precondition` section, fenced-block metadata, or custom skip exit codes.
Runtime guards belong inside the command block. Exit-code semantics are plain: `0` means success or intentional no-op;
non-zero means failure.

Commands run only after confirmation. If the user gives explicit bulk approval at the start of provisioning, the agent
may avoid repeated confirmations for that run.

## Deployment State

Deployment state is a Markdown file with YAML frontmatter at `.agents/state/hosts/HOST/tilde.md` in the source
repository copy. `HOST` is the short name derived from `hostname -f`.

Frontmatter keys:

- `head`: the repository `HEAD` at provisioning time, from `git rev-parse HEAD`.
- `date`: provisioning time, from `date --iso-8601=seconds`.
- `done`: ordered map of provisioned module directories. Values are `ok`, `notok`, or `ignored`.

Example:

```markdown
---
head: a10a8ae3db88c91f792b54b76db93dc30e09341e
date: 2026-05-15T10:00:00+03:00
done:
  foo: ok
  bar: notok
  baz: ignored
---

Optional details, for example why `bar` failed.
```

Before writing deployment state, preserve the previous state file. Repeated provisioning at the same `head` may run; in
that case, only `notok` modules are candidates while `ok` and `ignored` modules are skipped.

The deployment state body is optional. Use it for details that may help resolve future `notok` modules.

Deployment state is first written to the repository copy where actions were applied. For local provisioning, this is the
local repository. For SSH provisioning, this is the target machine's repository copy.

The local repository is the practical deployment state archive. After remote provisioning, if the target repository does
not sync back through Dropbox, copy the target state file back into the local archive at
`.agents/state/hosts/HOST/tilde.md`. When the target repository is Dropbox-backed, no explicit state copy-back is
required. If the target repository is a Git clone and `.agents/state` is ignored by Git, this is normal; state is
produced on the target and copied back at the end when needed.

## Command Semantics

Tilde commands are a prompt contract, not a strict shell CLI. Treat `$tilde [command] [subject...] [qualifiers...]` as a
compact way to express intent. The command name is stable; the subject and qualifiers may be natural language. Do not add
a canonical command-scope axis. Each command defines its own semantics, and explicit arguments refine the target.

Bare `$tilde` means `update`. This default should handle the most common returning-user workflow after deployment:
reconcile the repository's desired state with the live home, then update managed external resources. It is still
proposal-first and must show the planned phases before making changes.

`$tilde help` is the read-only command reference. Start the output by showing the general format,
`$tilde <command> [<arguments>...]`. With no subject, it lists all built-in and preference-sensitive commands with a
one-line action description for each. With one command subject, it shows detailed help for only that command. If the
subject is not a Tilde command, say that no such Tilde command exists, then behave like bare `$tilde help`.

Use this action inventory for help output:

| Command | Action |
| --- | --- |
| `adopt` | Adopt an app, config, package, or path into public `tilde` or private `tilde-`. |
| `archive` | Move selected home content into an archive according to private policy. |
| `apply` | Apply the lower-level provisioning plan after confirmation. |
| `bootstrap` | Run or guide the fresh-host bootstrap prelude. |
| `clean` | Propose conservative cleanup for selected home content. |
| `dedupe` | Find and propose handling for duplicate selected home content. |
| `deploy` | Prepare a local or remote host and apply desired state. |
| `doctor` | Diagnose deployment, repository, host, router, and managed-link health. |
| `help` | Show all commands or detailed help for one command. |
| `links` | Inspect managed links and copies. |
| `organize` | Propose organization changes for selected home content. |
| `plan` | Show the lower-level provisioning plan without applying it. |
| `refresh` | Update managed external resources only. |
| `repair` | Retry failed deployment modules at the recorded state. |
| `status` | Show a short read-only deployment and home-router summary. |
| `update` | Reconcile desired state, then refresh managed external resources. |
| `upgrade` | Run broad package-manager upgrades after explicit confirmation. |

After the table, show these short help notes:

- Detailed command help: `$tilde help <command>`
- Bare `$tilde` means `update`.

Commands are proposal-first when they may change files, repositories, packages, or remote hosts. A proposal must describe
the intended action and wait for confirmation before writes, moves, removals, package changes, or repository edits.

### User Interaction

Use the agent runtime's clearest available interaction surface for confirmations, choices, and menus. Prefer native
structured confirmation or choice UI over raw terminal-style prompts such as `[Y/n]` when the runtime provides one. In
Codex, use the available structured user-input or AFALA-style tool when it is available and appropriate; in other agents,
use the equivalent native interaction mechanism when one exists.

If no structured UI is available, ask in plain language with explicit choices. Name the action, target host or path, and
blast radius. For multi-choice decisions, present a short numbered or bulleted list with one recommended option when
there is a safe default. For destructive or preference-sensitive actions, make the opt-in explicit; do not rely on a
single-letter default prompt.

When deployment has completed, commands may be issued from the home directory. For command routing, deployment is
complete when the home router can resolve the canonical Tilde repository. Deployment state, when present, is additional
status evidence rather than the router signal. When deployment has not completed or the home router cannot find the
repository, commands that would mutate home stop and guide the user toward deployment, bootstrap, or an explicit
repository path.

### Home Router

`.agents/skills/tilde/assets/AGENTS.md` is the canonical public home router template. Tilde deployment links it directly
to `~/AGENTS.md` as a core managed link, outside module frontmatter. Keep the router short. It routes agents; it does
not carry detailed private preferences or repository development policy. The repository root `AGENTS.md` remains
repository-local instructions for agents working inside this checkout.

The router should tell agents to:

- Treat the current directory as the user's home workspace.
- Resolve the canonical Tilde repository from the resolved symlink target chain of `~/AGENTS.md` when possible. The
  normal target is `.agents/skills/tilde/assets/AGENTS.md`.
- Starting at the target file's parent directory, walk ancestors only until finding a directory that contains both
  `.agents/skills/tilde/SKILL.md` and `.agents/skills/tilde/references/spec.md`. That directory is the canonical Tilde
  repository. This is a bounded ancestor walk, not a home search.
- If symlink resolution is unavailable or the target does not identify a Tilde repository, resolve from the current
  repository when already inside Tilde, then from an explicit user-provided repository path. Do not search the whole home
  directory for a repository.
- Discover sibling `tilde-` as the private companion repository when present.
- Avoid recursive home scans by default.
- Read `tilde-/AGENTS.md` before preference-sensitive home commands when that file exists.
- Require explicit confirmation for destructive actions and for repository writes.

Do not put personal home layout policy in the public router. Layout policy such as localized directory names, cleanup
preferences, archive rules, and organization rules belongs in `tilde-/AGENTS.md` when private policy exists. Public
behavior may use cheap runtime detection, such as XDG user dirs, but must not assume a personal layout.

### Core Managed Links

Tilde deployment has core managed links that are not owned by any root module. They are planned before modules and use
the same confirmation and application semantics as normal link actions.

Core links:

- `.agents/skills/tilde/assets/AGENTS.md` -> `~/AGENTS.md`

Do not place the home router link in the `agents` module. The `agents` module owns shared `~/.agents` assets; the home
router is a Tilde deployment invariant.

### Built-In Commands

Built-in command semantics:

- `help`: show the Tilde command reference. Usage: `$tilde help [command]`.
- `deploy`: deploy Tilde desired state to a local or remote host. It may perform bootstrap, repository preparation,
  planning, applying, and state copy-back according to host kind.
- `bootstrap`: run or guide the explicit bootstrap prelude for a fresh or underprovisioned target.
- `update`: perform the normal returning-user maintenance flow. It first reconciles Tilde desired state with the live
  home using lower-level `apply` semantics, then refreshes managed external resources using lower-level `refresh`
  semantics. It is a prompt-level orchestration command, not a separate `bin/plan --mode` value.
- `plan`: show the lower-level provisioning plan without applying it.
- `apply`: apply the lower-level provisioning plan after confirmation.
- `refresh`: update managed external resources only.
- `repair`: retry modules marked `notok` in deployment state.
- `upgrade`: run broad package-manager upgrades only on explicit request after describing scope.
- `status`: print a short read-only summary of deployment state and concise home-router or host-kind facts when
  available. It should not perform broad diagnostics.
- `doctor`: diagnose host/home health, deployment readiness, repository discovery, Dropbox/Git consistency, dirty
  worktrees, broken managed links, and missing state. It reports findings and suggestions, but it is not a whole-home
  audit.
- `links`: inspect managed links and copies. It is limited to the managed surface and known managed targets.
- `adopt`: inspect a requested app, config, package identity, or explicit path; propose how to move it into public
  `tilde` or private `tilde-`; and wait for confirmation before any write.

Preference-sensitive commands:

- `clean`
- `organize`
- `archive`
- `dedupe`

These commands depend on personal policy. Before running them, read `tilde-/AGENTS.md` when available. If no private
policy exists, produce only conservative proposals or suggest creating private policy; do not infer aggressive cleanup or
organization rules from the public repository.

`private` is not a built-in command. Use `tilde-` as the private companion repository and policy source. Natural-language
requests such as "adopt this into private" or "check the private repo" are valid qualifiers on other commands.

### Bounded Discovery

Do not recursively scan `$HOME` by default. Do not run `find $HOME`, `fd $HOME`, or equivalent broad recursive searches
unless the user explicitly requests a broad scan after the cost and scope are described.

Use bounded discovery:

- Existing public and private modules.
- Explicit paths provided by the user.
- Known managed targets from active module definitions.
- Cheap standard home metadata, such as XDG user dirs.
- Known application/config locations relevant to the requested subject.
- Cheap package or application metadata when available.

Localized subjects such as `downloads`, `indirilenler`, or `İndirilenler` should be resolved through runtime detection
or private policy when possible. Hardcoded names are fallback only.

### Adoption

For `$tilde adopt SUBJECT`, resolve the subject in this order:

1. Existing public or private module.
2. Explicit path when the subject is path-like.
3. Known app or config locations for the target platform.
4. Cheap package, application, bundle, or desktop metadata.
5. A clarification question.

Adoption proposals should decide public versus private placement conservatively. Secrets, credentials, license files,
host-specific values, private endpoints, account identifiers, and uncertain private material belong in `tilde-` or
require clarification. Public-safe configuration may go in `tilde`.

Adoption must also propose `links` versus `copies`. Use `links` for stable user-owned config. Use `copies` for files or
directories that target applications are expected to overwrite.

Before writing an adoption, inspect dirty state in the target repository and in `tilde-` when it will be touched. Do not
overwrite uncommitted work without explicit confirmation.

### Home Workflow State

Home-management proposals are not deployment state. Do not write adoption, cleanup, organization, or diagnostic
proposals to `.agents/state/hosts/HOST/tilde.md`.

For broad, risky, multi-file, multi-session, or interrupted home workflows, use `.agents/state/tasks/` as local task
state when useful. Keep durable decisions in this spec or in reviewed notes, not in deployment state.

### Apply Vocabulary

Follow-up phrases such as `apply`, `apply proposal`, `do it`, or `adopt it` refer to the latest proposal only when the
reference is unambiguous. If there is any ambiguity, summarize the proposal again before asking for confirmation.

With an active unambiguous proposal, `apply` applies that proposal after confirmation. Without an active proposal,
`apply` means the lower-level provisioning apply mode.

If an action partially fails, report what changed, what did not change, and what remains. Do not promise automatic
rollback unless a rollback plan was explicitly prepared.

Remote destructive or preference-sensitive commands require confirmation that names the remote host, target home path,
and action set.

## Deployment

Deployment is the user-facing operation that prepares a host and applies Tilde desired state. It may include bootstrap,
repository preparation, provisioning plan generation, provisioning apply, and deployment state copy-back.

Deployment must not assume a fixed repository location. Links and copies resolve from the repository copy that is
actually being applied. Deployment may run locally or over SSH. If the target machine already has a Dropbox-backed
repository copy, use that copy. If the repository is cloned to a target machine, the default location is
`~/.local/src/<repo-name>`. The directory name is the repository's own name; do not force it to `home`.

### Host Kinds

Choose the host kind by asking whether the target repository copy is Dropbox-backed. A personal physical machine has no
special provisioning semantics by itself; it only changes the likelihood that Dropbox is available.

| Kind | When | Bootstrap | Repository copy | Deployment state handling | Default flow |
| --- | --- | --- | --- | --- | --- |
| `dropbox` | Target has a synced Dropbox copy of this repository. This is typical for personal physical machines when Dropbox quota and device limits allow it. | Run the repo-local bootstrap from the target checkout. | Use the target's Dropbox-backed checkout. | Dropbox sync carries state; no explicit copy-back. | local apply or `remote-dropbox` |
| `git` | Target does not use Dropbox for this repository. This covers VPS hosts and personal machines where Dropbox is unavailable or undesired. | Deliver bootstrap before cloning, usually over SSH or the public bootstrap URL when available. | Clone or fetch into `~/.local/src/<repo-name>`. | Write deployment state on target, then copy it back to the local archive when orchestration is remote. | `remote-git` or local git-backed apply |
| `self` | A user clones the public repository or a fork and applies it on the same machine. | Prefer the public bootstrap URL when available; otherwise run repo-local bootstrap after cloning. | User-chosen checkout, usually `~/.local/src/<repo-name>`. | Local deployment state stays in that checkout; private archive and `tilde-` behavior are optional. | local apply |
| `any` | The target has an existing repository path whose branch, `HEAD`, or dirty state is intentionally accepted. | Use the existing checkout's bootstrap unless the target lacks the checkout, then deliver bootstrap first. | Use the provided path as-is. | Copy deployment state back unless the path is known to sync. | `remote-any` |

Dropbox mode is valid only when the target machine's repository copy syncs through Dropbox. If a personal physical
machine cannot or should not use Dropbox, treat it as `git`.

### Dropbox Preflight

Dropbox installation and account linking are interactive preconditions. Tilde must not treat Dropbox installation as an
unattended provisioning action.

When the chosen host kind is `dropbox`, the agent first checks the target context for a Dropbox-backed checkout of this
repository. For remote SSH orchestration, inspect the target machine, not the local machine. If the checkout is missing,
unreadable, or clearly not synced, stop before normal `apply` and guide the user through the platform-appropriate manual
Dropbox setup:

- macOS: install the Dropbox app, sign in, select or sync the repository, and wait until the checkout is present.
- Linux desktop: install the Dropbox package or daemon, sign in through the interactive flow, select or sync the
  repository, and wait until the checkout is present.
- Headless Linux or VPS: guide the user through Dropbox's headless Linux setup and account-link flow, then wait until
  the repository checkout is present. If headless Dropbox setup is not practical or the user declines it, switch to
  `git` host kind only after explicit confirmation.

After the user confirms Dropbox is installed, linked, and synced, re-run the preflight. Only then run repo-local
bootstrap from the Dropbox-backed checkout and continue to plan/apply.

Do not create a separate Git clone on a target that was selected as `dropbox` unless the user explicitly changes the
host kind to `git`. This avoids two competing Tilde checkouts on personal machines.

### Bootstrap

The bootstrap helper is `bin/bootstrap`. It prepares the smallest baseline needed for normal
provisioning: transport tools, Homebrew, Ruby, `curl`, and `git`. Bootstrap must be Bash, must not require Ruby, must be
idempotent, and must remain outside normal module state.

Bootstrap has two separate concerns:

- **Delivery**: get the bootstrap script onto the target when the repository is not there yet.
- **Preparation**: run the bootstrap script so the target can clone or operate the repository and run the planner.

When the repository is already present on the target, run bootstrap from the repository:

```bash
bin/bootstrap
```

When bootstrapping a remote target that does not have the repository yet, deliver the script over SSH:

```bash
ssh HOST 'bash -s' < bin/bootstrap
```

When `tilde.roktas.dev` exists as the GitHub-backed public site for this repository, prefer the public bootstrap endpoint
where HTTPS and `curl` are available:

```bash
curl -fsSL https://tilde.roktas.dev/bootstrap | bash
```

This public transport is the default for `self` installs and a good default for `git` targets when the target can reach
the site. SSH delivery remains the fallback for private in-flight changes, targets without `curl`, locked-down networks,
or orchestrated installs that should use the local checkout's exact bootstrap script.

A public or fork-based install may also fetch the same script from official release or raw Git metadata, but that
transport must be documented separately and should prefer immutable or trusted references when possible.

On apt-based Linux, bootstrap installs the small base needed for Homebrew, such as `build-essential`, `ca-certificates`,
`curl`, `file`, `git`, and `procps`, then installs Homebrew and installs `curl`, `git`, and `ruby` through Homebrew.

On macOS, bootstrap checks for Xcode Command Line Tools first, installs Homebrew, and installs `curl`, `git`, and
`ruby` through Homebrew. If Command Line Tools installation is started, bootstrap stops and the user reruns it after the
platform installer finishes.

### Remote Modes

- `remote-git`: deterministic default for SSH provisioning when the target does not have a Dropbox-backed checkout.
  Prepare the target repository by cloning or fetching it, usually under `~/.local/src/<repo-name>`. Use `main` and the
  latest pushed commit unless instructed otherwise. Require a clean local worktree and a pushed commit.
- `remote-dropbox`: use the target repository that already exists under Dropbox. Local and target Git `HEAD` do not need
  to match. State is expected to sync through Dropbox.
- `remote-any`: use the provided target repository path as-is. This is intentionally less deterministic; call out
  branch, `HEAD`, and dirty-state uncertainty and continue only with explicit confirmation.

In all remote modes, resolve links, copies, and home inspections against the target machine's home directory and target
repository copy, not the local orchestrating repository. Write deployment state on the target first. If the target
repository is not Dropbox-synced, fetch the resulting state file back into the local archive before finishing.

## Provisioning

Provisioning is the lower-level module operation performed during deployment. It is intended to be idempotent where
practical, but it is not perfectly idempotent.

### Modes

- `apply`: apply repository desired state to the target host. This covers first provisioning and normal state/`HEAD`
  reconciliation, including new links, copies, packages, and selected special sections.
- `refresh`: update only managed external resources: active plan packages and `README.md` `Update` sections. It may run
  even when `HEAD` is unchanged.
- `repair`: retry modules marked `notok` in deployment state at the same `HEAD`.
- `upgrade`: broad package-manager upgrade mode. It may affect packages outside this repository and runs only on
  explicit user request after scope is described.

`apply` and `repair` are deployment-state/`HEAD` driven. `refresh` and `upgrade` are external-resource/time driven.
The user-facing `update` command runs the `apply` and `refresh` phases in that order, after confirmation, so new desired
state and existing managed external resources can both be brought current.

### Init

- Read current deployment state. Missing deployment state means a fresh install.
- Compare repository `HEAD` with deployment state `head`.
- Identify changes that require provisioning. Frontmatter changes usually matter; changes to already-linked module files
  usually do not require relinking.
- Process changed or required modules.

### Traverse

- Plan core managed links first.
- Process the active platform module first.
- Process the active platform variant second, when present.
- Process active other root modules alphabetically.
- Enter each module directory, read `README.md`, load frontmatter, and merge `all` with the active platform scope.
- Interpret `HEAD`/deployment-state differences to produce the active provisioning set. Added packages, added links,
  removed links, and added copies matter. Removed packages and removed copies are not automatic removal actions.
- In `apply`, run install and link phases.
- In `refresh`, refresh packages and selected `Update` sections in managed scope only.
- In `repair`, retry `notok` modules at the same `HEAD`.
- In `upgrade`, run broad package-manager updates only after explicit confirmation.
- Save deployment state.

### Ordering

- The active platform module runs first.
- The active platform variant runs immediately after the platform module.
- Other root modules run alphabetically by directory name. `misc` has no special position.
- A future `order` frontmatter key may be interpreted as numeric weight. Modules without `order` use the default weight;
  ties keep alphabetical order.

### Install

- Run `Preinstall` instructions when present.
- Install added packages from the active provisioning set, grouped by package type. Do not remove packages removed from
  frontmatter.
- Run `Install` and `Postinstall` instructions when present.

### Link

- Run `Prelink` or `Presetup` instructions when present.
- Create added symlinks.
- Create added copies.
- Remove a dropped link only if the target is a symlink into this repository or a dangling symlink. Do not touch dropped
  link targets that are not symlinks or point outside this repository.
- Do not automatically remove dropped copy targets.
- Run `Link`, `Postlink`, or `Setup` instructions when present.

### Update

- Run `Update` instructions only in `refresh` or explicitly requested `upgrade`. Do not run them during normal `apply`.

## Package Installation

Group package installs by package type, present commands in the plan, and run them only after confirmation. Package
removal is never inferred from removed frontmatter entries.

Installation commands:

- `brew:<name>`: `brew install <name>`
- `cask:<name>`: `brew install --cask <name>`
- `deb:<name>`: `sudo apt install -y <name>`; run `sudo apt update` first when the package index may be stale. In
  non-interactive scripts, prefer `sudo apt-get install -y <name>`.
- `npm:<name>`: `bun install -g <name>`
- `gem:<name>`: `gem install --user-install --no-document <name>` unless local RubyGems config already routes installs
  to a user-writable gem home. Do not use `sudo gem install`.
- `egg:<name>`: `uv tool install <name>`. If the package does not expose the expected executable, inspect package docs
  and use a module README special section for package-specific flags such as `--with`.
- `flatpak:<app-id>`: `flatpak install --user flathub <app-id>` unless the module explicitly requires system-wide
  Flatpak install.
- `scoop:<name>`: `scoop install <name>`
- `github:<owner>/<repo>`: inspect official release metadata with the GitHub API, GitHub MCP, or `gh release` commands.
  Select the asset that matches target platform and architecture, download to a temp directory, verify checksum or
  provenance when provided, extract it, and copy executables to `~/.local/bin`. If asset or executable layout is
  ambiguous, ask before installing.

For `github` assets, prefer official release metadata over scraping HTML:

```bash
gh release view --repo OWNER/REPO --json tagName,assets
gh release download --repo OWNER/REPO --pattern 'PATTERN'
```

## Package Updates

Default update scope is managed packages only: update only package entries present in the active provisioning plan, one
package at a time or grouped by explicit package names. Do not run package-manager-wide upgrade commands unless the user
explicitly asks for a full/global update.

Before managed updates, run metadata refresh commands at most once per package manager represented in the confirmed
update set:

- `brew update`
- `sudo apt update`
- `scoop update`
- `flatpak update --appstream`

Managed update commands:

- `brew:<name>`: `brew upgrade <name>`
- `cask:<name>`: `brew upgrade --cask <name>`. If the cask is excluded from normal upgrades because it uses
  `version :latest` or self-updates, use `brew upgrade --cask --greedy <name>` only after calling out that extra scope.
- `deb:<name>`: `sudo apt-get install --only-upgrade -y <name>` after `sudo apt update`. If the package may not be
  installed yet, treat it as an install action.
- `npm:<name>`: `bun update -g <name>`
- `gem:<name>`: `gem update --user-install --no-document <name>`. Do not use bare `gem update`.
- `egg:<name>`: `uv tool upgrade <name>`. Use `uv tool install <name>` when changing version constraints or install
  flags.
- `flatpak:<app-id>`: `flatpak update --user <app-id>` for per-user installs created by this repository.
- `scoop:<name>`: run `scoop update` first, then `scoop update <name>`.
- `github:<owner>/<repo>`: inspect latest release assets again, compare with the installed binary when possible, and
  replace the executable only after selecting the matching asset.
