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

Remote SSH orchestration must not rely on the target user's login shell. The canonical multi-command remote form is a
POSIX `sh -s` heredoc; agents must use this shape for remote dry-run, update, deploy, status, and doctor snippets unless
the user explicitly asks for a different transport:

```sh
ssh HOST sh -s <<'SH'
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
skill="$HOME/.agents/skills/tilde"
"$skill/bin/plan" --repo "$HOME/Dropbox/home" --mode apply --host HOST --format json > /tmp/plan.json
SH
```

The quoted heredoc delimiter prevents local-shell expansion; variables expand on the target inside `sh`. This shape
keeps the remote body visible and avoids nested quote bugs. Do not begin an SSH command with login-shell syntax such as
`set -e; ...`; targets may use Fish, Zsh, or another shell with different `set` semantics. Do not compress
multi-command remote orchestration into `ssh HOST 'sh -c ...'`, and do not use `bash -lc` as default remote glue on
macOS, because `bash` may resolve to the old system Bash instead of a Homebrew Bash. Use Bash only for explicit Bash
script entrypoints such as `bin/bootstrap` or scripts with a Bash shebang. When a post-bootstrap remote step genuinely
requires Homebrew Bash, resolve that interpreter target-locally from the Homebrew environment or an explicit target path
instead of assuming `bash` means it. Do not rely on login-shell startup files for `PATH`; set any required environment
inside the remote snippet.

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
public-only deployment. When private is included, clone or fetch it on the target alongside the public repository,
normally under `~/.local/src/<private-repo-name>`.

If a private data repository is configured but the target private checkout is missing, unreadable, not synced, or does
not confirm its private role, stop before normal install and guide the user to sync or initialize the private checkout.
Continue without a private checkout only when the user has no private data repository configured or explicitly confirms
a public-only deployment.

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
| `dropbox` | Target has a synced Dropbox copy of the public data repository. This is typical for personal physical machines when Dropbox quota and device limits allow it. | Run the installed skill bootstrap or the bootstrap helper available in the target context. | Use the target's Dropbox-backed public checkout and configured private checkout. | Target state under `~/.local/state/tilde` is authoritative; Dropbox may sync repository files, not runtime state. | local install or `remote-dropbox` |
| `git` | Target does not use Dropbox for the public data repository. This covers VPS hosts and personal machines where Dropbox is unavailable or undesired. | Deliver bootstrap before cloning, usually over SSH or the public bootstrap URL when available. | Clone or fetch into `~/.local/src/<repo-name>`. | Write state on the target, then optionally mirror it under the controller's `~/.local/state/tilde/remotes/HOST/`. | `remote-git` or local git-backed install |
| `self` | A user clones the public data repository or a fork and applies it on the same machine. | Prefer the public bootstrap URL when available; otherwise use the installed skill bootstrap after cloning. | User-chosen checkout, usually `~/.local/src/<repo-name>`. | Local deployment state stays under `~/.local/state/tilde`. Private data repository behavior is optional. | local install |
| `any` | The target has an existing repository path whose branch, `HEAD`, or dirty state is intentionally accepted. | Use the installed skill bootstrap unless the target lacks the skill, then deliver bootstrap first. | Use the provided path as-is. | Write state on the target and mirror it only when requested or useful for orchestration. | `remote-any` |

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

Run `bin/preflight` in the target context to make the checkout check bounded and repeatable. Supply important
checkout-relative paths with `--require`; for example, require `AGENTS.md` for a data repository and `SKILL.md`,
`bin/plan`, and `bin/bootstrap` for the Tilde repository. A missing required path, unreadable Git `HEAD` or `HEAD` tree,
or Git tree that cannot be traversed blocks deployment. Do not use an unbounded full-object `git fsck` during ordinary
preflight; reserve deeper repository diagnosis for doctor flows.

On macOS, File Provider status such as an active download, a checkout not marked keep downloaded, or a checkout not
marked recursively downloaded is advisory. Report those flags, but let required-file and Git traversal checks decide
whether the checkout is usable.

Do not create a separate Git clone on a target that was selected as `dropbox` unless the user explicitly changes the
host kind to `git`. This avoids two competing public data checkouts on personal machines.

After the target checkouts are confirmed, resolve private policy and modules from the target private checkout. For
example, the steady-state `~/AGENTS.md` link should come from the target private data repository's `home/AGENTS.md`
when a private data repository is configured.

### Bootstrap

The bootstrap helper is `bin/bootstrap` in the installed skill. It prepares the smallest baseline needed for normal
provisioning: transport tools, Homebrew, Ruby, `curl`, and `git`. Bootstrap must be Bash, must not require Ruby, must be
idempotent, and must remain outside normal module state.

Bootstrap has two separate concerns:

- **Delivery**: get the bootstrap script onto the target when the installed skill is not there yet.
- **Preparation**: run the bootstrap script so the target can clone or operate repositories and run the planner.

When the installed skill is already present on the target, run bootstrap from the installed skill:

```bash
bin/bootstrap
```

When bootstrapping a remote target that does not have the installed skill yet, deliver the script over SSH:

```bash
ssh HOST 'bash -s' < bin/bootstrap
```

This is an explicit Bash script delivery exception, not the general remote orchestration shell. `bin/bootstrap` must
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
`curl`, `file`, `git`, and `procps`, then installs Homebrew and installs `curl`, `git`, and `ruby` through Homebrew.

On macOS, bootstrap checks for Xcode Command Line Tools first, installs Homebrew, and installs `curl`, `git`, and
`ruby` through Homebrew. If Command Line Tools installation is started, bootstrap stops and the user reruns it after the
platform installer finishes. Bootstrap must detect an existing Homebrew installation in standard macOS and Linuxbrew
locations even when non-interactive SSH does not put `brew` on `PATH`. After installing formulas, bootstrap uses the
Homebrew `curl` and keg-only Ruby paths for its own verification. Later remote processes that require Homebrew Ruby must
load the target Homebrew environment and Ruby formula path explicitly.

### Remote Modes

- `remote-git`: deterministic default for SSH provisioning when the target does not have a Dropbox-backed public data
  checkout. Prepare the target public repository by cloning or fetching it, usually under `~/.local/src/<repo-name>`.
  Prepare the private repository the same way only when it is configured or explicitly requested. Use `main` and the
  latest pushed commit unless instructed otherwise. Require a clean local worktree and a pushed commit.
- `remote-dropbox`: use the target public/private repositories that already exist under Dropbox. Local and target Git
  `HEAD` do not need to match, but repository identity and public/private roles must match. Runtime state stays under
  `~/.local/state/tilde` on the target.
- `remote-any`: use the provided target repository path as-is. This is intentionally less deterministic; call out
  branch, `HEAD`, and dirty-state uncertainty and continue only with explicit confirmation.

In all remote modes, resolve links, copies, and home inspections against the target machine's home directory and target
repository copies, not the local orchestrating repository. Write deployment state on the target first. The controller may
copy or summarize the target state into its read-only remote mirror before finishing.
