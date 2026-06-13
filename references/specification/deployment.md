# Tilde Deployment

## Deployment

Deployment is the user-facing operation that prepares a host and installs Tilde desired state from configured public and
private data repositories. It may include initialization, bootstrap/preflight, repository preparation, provisioning plan
generation, provisioning apply, and deployment state update.

Deployment must not assume a fixed data repository location. Links and copies resolve from the public/private repository
copies that are actually being applied. Deployment may run locally or over SSH. Commands that deploy, initialize,
inspect, diagnose, or update a remote host may accept a Git-like target syntax:

```text
$tilde deploy ssh:<host>
$tilde deploy ssh:<host> PUBLIC_REPO
$tilde deploy ssh:<host> --public PUBLIC_REPO --private PRIVATE_REPO
$tilde init ssh:<host> --public PUBLIC_REPO
$tilde update ssh:<host>
$tilde doctor ssh:<host>
$tilde status ssh:<host>
```

`ssh:<host>` identifies the target host. Public/private repository arguments identify the controller-side data
repositories by default. A future qualified syntax may distinguish controller-side sources from remote-side repository
paths if needed.

For `remote-dropbox`, controller-side public/private arguments are identity and discovery inputs, not target paths. The
agent must inspect the remote target and use the target's Dropbox-synced public/private repository checkouts for
planning and installation. Do not interpret a controller-side `--private` value as a remote filesystem path. Instead,
match the target private checkout through repository identity frontmatter, target-local Tilde state, the public
checkout's private pointer interpreted relative to the target checkout, the target home entrypoint, or confirmed sibling
discovery.

If no public/private arguments are given, Tilde resolves them from local state, home-entrypoint metadata, or the remote
target's configured state according to the command's semantics.

Remote SSH orchestration must not rely on the target user's login shell. Use `bin/tilde ssh` for Tilde-controlled
multi-command remote work when the runtime route is available. The route reads the heredoc body from stdin, sets a
target PATH prelude, and executes the body through the visible POSIX `ssh HOST sh -s --` shape:

```sh
bin/tilde ssh HOST <<'SH'
skill="$HOME/.agents/skills/tilde"
"$skill/bin/tilde" plan --repo "$HOME/Dropbox/home" --mode apply --host HOST --format json > /tmp/plan.json
SH
```

The quoted heredoc delimiter prevents local-shell expansion; variables expand on the target inside `sh`. This route
keeps the remote body visible and avoids nested quote bugs. Do not begin an SSH command with login-shell syntax such as
`set -e; ...`; targets may use Fish, Zsh, or another shell with different `set` semantics. Do not compress
multi-command remote orchestration into `ssh HOST 'sh -c ...'`, and do not use `bash -lc` as default remote glue on
macOS, because `bash` may resolve to the system Bash instead of a Homebrew Bash. Use Bash only for explicit Bash script
entrypoints such as `libexec/boot` or scripts with a Bash shebang. When a post-bootstrap remote step genuinely requires
Homebrew Bash, resolve that interpreter target-locally from the Homebrew environment or an explicit target path instead
of assuming `bash` means it. Do not rely on login-shell startup files for `PATH`; set any required environment inside
the remote snippet or let `bin/tilde ssh` provide the standard Tilde prelude.

Do not use these forms for multi-command Tilde orchestration:

```sh
ssh HOST 'set -e; ...'
ssh HOST 'sh -c ...'
ssh HOST 'bash -lc ...'
```

If the target machine already has a Dropbox-backed public data repository copy, use that copy. If the public repository
is cloned to a target machine, the default location is `~/.local/src/<repo-name>`. The directory name is the
repository's own name; do not force it to `home`.

For `remote-git`, a public data repository is required. The private data repository is optional: include it when it is
configured by controller state, public repository frontmatter, or an explicit `--private PRIVATE_REPO`; otherwise run a
public-only deployment. When private is included, prepare it on the target alongside the public repository, normally
under `~/.local/src/<private-repo-name>`.

For `remote-git`, the default private repository transport is a controller-side Git bundle, not target-side private
GitHub authentication. The controller verifies the local private checkout is clean and at its upstream commit, creates a
full bundle for the selected branch, transfers it over the existing SSH path, and the target clones or fetches that
bundle into the normal target-local checkout. Target-side private Git authentication is opt-in only, for hosts where the
user explicitly wants deploy keys, `gh auth`, SSH agent forwarding, or another private Git credential on the target.

Bundle transport must update existing target checkouts with `git fetch BUNDLE refs/heads/BRANCH:refs/remotes/origin/BRANCH`
followed by `git merge --ff-only origin/BRANCH`. It must stop when the target checkout is dirty, on the wrong branch, or
cannot fast-forward. It must write only temporary bundle files on the target and remove them before closeout. The
controller may use `bin/tilde checkout remote` for this transport.

If `remote-git` bundle transport is selected and the target private checkout is missing, create it from the bundle
before planning. Stop only when an existing target private path is not a Git checkout, is dirty, is on the wrong branch,
cannot fast-forward from the bundle, or does not confirm its private role after checkout preparation. For
`remote-dropbox` or explicit target-side private Git transport, a missing, unreadable, unsynced, or role-mismatched
private checkout remains a blocker. Continue without a private checkout only when the user has no private data
repository configured or explicitly confirms a public-only deployment.

### User Scenarios

When the Tilde skill is installed but no home repositories exist yet, the primary low-friction path is:

```text
$tilde create
$tilde adopt zsh
$tilde adopt git
$tilde deploy dry-run
$tilde deploy
```

`deploy` may also guide this scenario in one journey:

```text
$tilde deploy
```

With no explicit repository path, `create` and first-run `deploy` use default-location discovery: prefer the
conventional `home`/`home-` public/private pair directly under `~/Dropbox`, then under `~/.local/src`. If the public
path does not exist, `deploy` may propose a `create` phase. A newly created empty repository should not force immediate
provisioning. Offer clear choices such as finishing initialization, running bootstrap checks, starting adoption, or
applying an empty/minimal desired state.

When public/private home repositories already exist, the typical local flow is:

```text
$tilde deploy
```

The equivalent explicit flow is:

```text
$tilde init
$tilde deploy
```

This flow identifies public/private repositories, validates repository roles, writes local Tilde state after
confirmation, writes or updates the home entrypoint after confirmation, runs bootstrap/preflight when needed, generates
a provisioning plan, and applies only after explicit confirmation.

After repository paths are resolved for a local or remote deployment, write the target's
`~/.local/state/tilde/config.yml` before final status. The config records the target-local installed skill path and
target-local public/private repository paths. For remote deployment, controller-side paths are never written into the
target config.

After a host has already been deployed, the normal returning-user flow is:

```text
$tilde update
```

For a remote host:

```text
$tilde update ssh:<host>
```

Use `update dry-run` or `update plan-only` when the user wants the returning-user proposal without applying it.

Plain `update` reconciles desired state, refreshes links, and runs the fast update path for represented system package
managers. It is equivalent to the public returning-user flow of `internal.install` followed by
`internal.refresh(scope=fast)`, after confirmation.

When the host already has enough runtime to read repositories and run the planner but bootstrap or package managers are
not available, use `align` to reconcile only links and copies. This keeps environment files and other managed symlinks
current without running bootstrap, Homebrew, apt, casks, GitHub release installers, or module scripts.

Use `update full` when the user wants full managed refresh: fast update plus managed non-system package declarations and
module `Update` sections. Use `upgrade` when the user wants the widest update: `update full` plus broad or aggressive
package-manager upgrades that may affect packages not declared by Tilde.

The update command scope ladder is:

```text
update < update full < upgrade
```

After accepting an adoption proposal for a new app, config, package, or explicit path, apply the changed desired state
through the returning-user update flow:

```text
$tilde adopt APP_OR_PATH
$tilde update dry-run
$tilde update
```

To apply the same accepted desired-state change to a remote host that has already been deployed:

```text
$tilde adopt APP_OR_PATH
$tilde update ssh:<host> dry-run
$tilde update ssh:<host>
```

`adopt` is a data-repository operation; `update` applies the accepted desired-state change to the selected target host.

For a minimal VPS or other remote host without Dropbox, use `remote-git`:

```text
$tilde deploy ssh:<host> --public PUBLIC_REPO
```

Add the private data repository only when private modules or policy should be installed on that host:

```text
$tilde deploy ssh:<host> --public PUBLIC_REPO --private PRIVATE_REPO
```

### Host Kinds

Choose the host kind by asking whether the target repository copy is Dropbox-backed. A personal physical machine has no
special provisioning semantics by itself; it only changes the likelihood that Dropbox is available.

| Kind | When | Bootstrap | Repository copy | Deployment state handling | Default flow |
| --- | --- | --- | --- | --- | --- |
| `dropbox` | Target has a synced Dropbox copy of the public data repository. This is typical for personal physical machines when Dropbox quota and device limits allow it. | Run the installed skill bootstrap only when the baseline is missing or suspect. | Use the target's Dropbox-backed public checkout and configured private checkout. | Target state under `~/.local/state/tilde` is authoritative; Dropbox may sync repository files, not runtime state. | local install or `remote-dropbox` |
| `git` | Target does not use Dropbox for the public data repository. This covers VPS hosts and personal machines where Dropbox is unavailable or undesired. | Deliver bootstrap before cloning only when the target lacks the baseline needed to clone and plan. | Clone or fetch into `~/.local/src/<repo-name>`. | Write state on the target, then optionally mirror it under the controller's `~/.local/state/tilde/remotes/HOST/`. | `remote-git` or local git-backed install |
| `self` | A user clones the public data repository or a fork and applies it on the same machine. | Prefer the public bootstrap URL only when baseline tools are missing; otherwise use the existing checkout and tools. | User-chosen checkout, usually `~/.local/src/<repo-name>`. | Local deployment state stays under `~/.local/state/tilde`. Private data repository behavior is optional. | local install |
| `any` | The target has an existing repository path whose branch, `HEAD`, or dirty state is intentionally accepted. | Use the installed skill bootstrap only when baseline tools are missing or suspect. | Use the provided path as-is. | Write state on the target and mirror it only when requested or useful for orchestration. | `remote-any` |

Dropbox mode is valid only when the target machine's repository copy syncs through Dropbox. If a personal physical
machine cannot or should not use Dropbox, treat it as `git`.

### Dropbox Preflight

Dropbox installation and account linking are interactive preconditions. Tilde must not treat Dropbox installation as an
unattended provisioning action.

When the chosen host kind is `dropbox`, the agent first checks the target context for Dropbox-backed checkouts of the
public data repository and any configured private data repository. For remote SSH orchestration, inspect the target
machine, not the local machine. If a required checkout is missing, unreadable, or clearly not synced, stop before normal
install and guide the user through the platform-appropriate manual Dropbox setup:

- macOS: install the Dropbox app, sign in, select or sync the repository, and wait until the checkout is present.
- Linux desktop: install the Dropbox package or daemon, sign in through the interactive flow, select or sync the
  repository, and wait until the checkout is present.
- Headless Linux or VPS: guide the user through Dropbox's headless Linux setup and account-link flow, then wait until
  the repository checkout is present. If headless Dropbox setup is not practical or the user declines it, switch to
  `git` host kind only after explicit confirmation.

After the user confirms Dropbox is installed, linked, and synced, re-run the preflight. Only then run bootstrap when
needed and continue to plan/install.

Run `bin/tilde preflight` in the target context to make the checkout check bounded and repeatable. Supply important
checkout-relative paths with `--require`; for example, require `AGENTS.md` for a data repository and `SKILL.md`,
`bin/tilde`, `bin/sudo`, `libexec/plan`, `libexec/apply`, and `libexec/boot` for the Tilde repository. A missing
required path, unreadable Git `HEAD` or `HEAD` tree, or Git tree that cannot be traversed blocks deployment. Do not use
an unbounded full-object `git fsck` during ordinary preflight; reserve deeper repository diagnosis for doctor flows.

Preflight starts with a bootstrap check. If compatible bootstrap state is already recorded in the target host state, the
check returns through the fast path without probing the system. If that state is missing, stale, or incompatible, the
check probes the bootstrap baseline and records an `ok` result in the host state when the probe succeeds. For normal
apply/update preflight, a failed probe is recoverable: preflight runs idempotent bootstrap, then re-runs
`bin/tilde boot --check --record`. If bootstrap still needs credentials, an interactive platform installer, network, or
another external action but the existing `git`, `ruby`, and `curl` runtime can run plan/apply, preflight reports the
deferred bootstrap and continues so desired-state reconciliation is not blocked. If bootstrap remains incomplete and the
required runtime is missing, preflight blocks. Use `bin/tilde preflight --bootstrap check` for check-only flows such as
dry-run contexts that must not install anything, `--bootstrap require` when the caller needs a complete baseline before
continuing, and `--bootstrap skip` only when a caller has already handled bootstrap.

On macOS, File Provider status such as an active download, a checkout not marked keep downloaded, or a checkout not
marked recursively downloaded is advisory. Report those flags, but let required-file and Git traversal checks decide
whether the checkout is usable.

Do not create a separate Git clone on a target that was selected as `dropbox` unless the user explicitly changes the
host kind to `git`. This avoids two competing public data checkouts on personal machines.

After the target checkouts are confirmed, resolve private policy and modules from the target private checkout. For
example, the steady-state `~/AGENTS.md` link should come from the target private data repository's `home/AGENTS.md`
when a private data repository is configured.

### Bootstrap

The bootstrap preparation route is `bin/tilde boot` in the installed skill, with `bin/bootstrap` as a focused wrapper.
Its implementation is `libexec/boot`. It prepares the smallest baseline needed for normal provisioning: transport tools,
Homebrew, Ruby, `curl`, and `git`. Bootstrap must be Bash, must not require Ruby, must be idempotent, and must remain
outside normal module state.

Bootstrap has two separate concerns:

- **Delivery**: get the bootstrap script onto the target when the installed skill is not there yet.
- **Preparation**: run the bootstrap script so the target can clone or operate repositories and run the planner.

When the installed skill is already present on the target but the bootstrap baseline is missing or suspect, run
bootstrap from the installed skill:

```bash
bin/tilde boot
```

Do not rerun bootstrap merely because deployment state was cleaned or a host is being redeployed. Clean state means the
planner and executor should behave like a fresh desired-state apply; it does not reset the target's bootstrap baseline.

`bin/tilde boot --check` checks the bootstrap baseline without installing packages. It reads the target host state
first: a compatible `bootstrap: {status: ok}` entry is a fast-path success. If `--probe` is given, or if compatible
state is missing, stale, or incompatible, it probes the system for the baseline tools. Failed checks must report the
missing or broken baseline part, such as stale state, missing Homebrew, missing Xcode Command Line Tools, a broken
Homebrew tool, or unavailable noninteractive `sudo`. `--record` records a successful probe into the existing host `state.md`
frontmatter. Normal bootstrap records the same `bootstrap` state after a successful install.

When bootstrapping a remote target that does not have the installed skill yet, deliver the script over SSH:

```bash
ssh HOST 'bash -s' < libexec/boot
```

This is an explicit Bash script delivery exception, not the general remote orchestration shell. `libexec/boot` must
remain compatible with the target's baseline Bash until Homebrew is installed and available.

When `tilde.roktas.dev` exists as the GitHub-backed public site for the installed skill, prefer the public bootstrap endpoint
where HTTPS and `curl` are available:

```bash
curl -fsSL https://tilde.roktas.dev/bootstrap | bash
```

This public transport is the default for `self` installs and a good default for `git` targets when the target can reach
the site. SSH delivery remains the fallback for private in-flight changes, targets without `curl`, locked-down networks,
or orchestrated installs that should use the local installed skill's exact bootstrap script.

A public or fork-based install may also fetch the same script from official release or raw Git metadata, but that
transport must be documented separately and should prefer immutable or trusted references when possible.

On apt-based Linux, bootstrap installs the small base needed for Homebrew, such as `build-essential`, `ca-certificates`,
`curl`, `file`, `git`, and `procps`, only when those prerequisites are not already present. It then installs Homebrew
and installs `curl`, `git`, and `ruby` through Homebrew. Bootstrap apt commands run non-interactively during remote or
scripted execution: use `sudo -n`, fail with a clear `sudo` reason when credentials are required, and avoid prompting in
the background. The official Linux Homebrew installer uses the supported `/home/linuxbrew/.linuxbrew` prefix and may
require sudo to create it; detect that noninteractive sudo need before starting the installer so preflight can defer
bootstrap cleanly. Before running apt, bootstrap checks apt/dpkg lock owners when the target has `fuser`; by default it
waits briefly and reports the owning processes. If unattended apt maintenance is stuck and the user approves stopping
it, rerun bootstrap with `TILDE_BOOTSTRAP_APT_LOCK=stop` so bootstrap stops `apt-daily`, `apt-daily-upgrade`, and
`unattended-upgrades` before retrying.

On macOS, bootstrap checks for Xcode Command Line Tools first, installs Homebrew, and installs `curl`, `git`, and
`ruby` through Homebrew. If Command Line Tools installation is started, bootstrap stops and the user reruns it after the
platform installer finishes. Bootstrap must detect an existing Homebrew installation in standard macOS and Linuxbrew
locations even when non-interactive SSH does not put `brew` on `PATH`. After installing formulas, bootstrap uses the
Homebrew `curl` and keg-only Ruby paths for its own verification. Later remote processes that require Homebrew Ruby must
load the target Homebrew environment and Ruby formula path explicitly.

### Privilege Handoff

Tilde-controlled package and section execution uses noninteractive sudo only. `bin/sudo` is a shim that is visible in the
Tilde execution `PATH`; it delegates to `bin/tilde sudo`, which calls the real sudo command with `-n`. Authentication,
TTY, and sudo policy failures emit `TILDE_PRIVILEGE_REQUIRED` and are reported as `deferred`.

When a remote deployment needs sudo and the target cannot run it noninteractively, present a user-run handoff command
instead of collecting a password. Generate it with:

```bash
bin/tilde sudo handoff --host HOST
```

The printed command runs the target's `bin/tilde sudo allow` in the user's terminal. That command validates and installs
`/etc/sudoers.d/tilde` for the target user and prints the matching cleanup command:

```bash
sudo rm -f /etc/sudoers.d/tilde
```

This rule grants broad root privilege to the target user and must be removed after the run. `bin/tilde sudo handoff
--copy` may copy the printed command to the local clipboard when a clipboard tool is available.

### Remote Modes

- `remote-git`: deterministic default for SSH provisioning when the target does not have a Dropbox-backed public data
  checkout. Prepare the target public repository by cloning or fetching it, usually under `~/.local/src/<repo-name>`.
  Prepare the private repository with controller-side bundle transport when it is configured or explicitly requested.
  Use `main` and the latest pushed commit unless instructed otherwise. Require a clean local worktree and a pushed
  commit. Target-side private Git authentication is an opt-in transport, not the default.
- `remote-dropbox`: use the target public/private repositories that already exist under Dropbox. Local and target Git
  `HEAD` do not need to match, but repository identity and public/private roles must match. Runtime state stays under
  `~/.local/state/tilde` on the target.
- `remote-any`: use the provided target repository path as-is. This is intentionally less deterministic; call out
  branch, `HEAD`, and dirty-state uncertainty and continue only with explicit confirmation.

In all remote modes, resolve links, copies, and home inspections against the target machine's home directory and target
repository copies, not the local orchestrating repository. Write deployment state on the target first. The controller may
copy or summarize the target state into its read-only remote mirror before finishing.
