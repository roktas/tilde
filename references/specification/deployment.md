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
$tilde deploy ssh:<host> ~/Dropbox/src/home
$tilde deploy ssh:<host> --public ~/src/home --private ~/src/home-
$tilde init ssh:<host> --public ~/src/home
$tilde update ssh:<host>
$tilde doctor ssh:<host>
$tilde status ssh:<host>
```

`ssh:<host>` identifies the target host. Public/private repository arguments identify the controller-side data
repositories by default. A future qualified syntax may distinguish controller-side sources from remote-side repository
paths if needed.

If no public/private arguments are given, Tilde resolves them from local state, router metadata, or the remote target's
configured state according to the command's semantics.

If the target machine already has a Dropbox-backed public data repository copy, use that copy. If the public repository
is cloned to a target machine, the default location is `~/.local/src/<repo-name>`. The directory name is the
repository's own name; do not force it to `home`.

### User Scenarios

When the Tilde skill is installed but no home repositories exist yet, the primary low-friction path is:

```text
$tilde create ~/Dropbox/src/home
$tilde adopt zsh
$tilde adopt git
$tilde deploy dry-run
$tilde deploy
```

`deploy` may also guide this scenario in one journey:

```text
$tilde deploy ~/Dropbox/src/home
```

If the public path does not exist, `deploy` may propose a `create` phase. A newly created empty repository should not
force immediate provisioning. Offer clear choices such as finishing initialization, running bootstrap checks, starting
adoption, or applying an empty/minimal desired state.

When public/private home repositories already exist, the typical local flow is:

```text
$tilde deploy ~/Dropbox/src/home
```

The equivalent explicit flow is:

```text
$tilde init ~/Dropbox/src/home
$tilde deploy
```

This flow identifies public/private repositories, validates repository roles, writes local Tilde state after
confirmation, writes or updates the home router after confirmation, runs bootstrap/preflight when needed, generates a
provisioning plan, and applies only after explicit confirmation.

### Host Kinds

Choose the host kind by asking whether the target repository copy is Dropbox-backed. A personal physical machine has no
special provisioning semantics by itself; it only changes the likelihood that Dropbox is available.

| Kind | When | Bootstrap | Repository copy | Deployment state handling | Default flow |
| --- | --- | --- | --- | --- | --- |
| `dropbox` | Target has a synced Dropbox copy of the public data repository. This is typical for personal physical machines when Dropbox quota and device limits allow it. | Run the installed skill bootstrap or the bootstrap helper available in the target context. | Use the target's Dropbox-backed public/private checkouts. | Target state under `~/.local/state/tilde` is authoritative; Dropbox may sync repository files, not runtime state. | local install or `remote-dropbox` |
| `git` | Target does not use Dropbox for the public data repository. This covers VPS hosts and personal machines where Dropbox is unavailable or undesired. | Deliver bootstrap before cloning, usually over SSH or the public bootstrap URL when available. | Clone or fetch into `~/.local/src/<repo-name>`. | Write state on the target, then optionally mirror it under the controller's `~/.local/state/tilde/remotes/HOST/`. | `remote-git` or local git-backed install |
| `self` | A user clones the public data repository or a fork and applies it on the same machine. | Prefer the public bootstrap URL when available; otherwise use the installed skill bootstrap after cloning. | User-chosen checkout, usually `~/.local/src/<repo-name>`. | Local deployment state stays under `~/.local/state/tilde`. Private `home-` behavior is optional. | local install |
| `any` | The target has an existing repository path whose branch, `HEAD`, or dirty state is intentionally accepted. | Use the installed skill bootstrap unless the target lacks the skill, then deliver bootstrap first. | Use the provided path as-is. | Write state on the target and mirror it only when requested or useful for orchestration. | `remote-any` |

Dropbox mode is valid only when the target machine's repository copy syncs through Dropbox. If a personal physical
machine cannot or should not use Dropbox, treat it as `git`.

### Dropbox Preflight

Dropbox installation and account linking are interactive preconditions. Tilde must not treat Dropbox installation as an
unattended provisioning action.

When the chosen host kind is `dropbox`, the agent first checks the target context for a Dropbox-backed checkout of the
public data repository. For remote SSH orchestration, inspect the target machine, not the local machine. If the checkout
is missing, unreadable, or clearly not synced, stop before normal install and guide the user through the
platform-appropriate manual Dropbox setup:

- macOS: install the Dropbox app, sign in, select or sync the repository, and wait until the checkout is present.
- Linux desktop: install the Dropbox package or daemon, sign in through the interactive flow, select or sync the
  repository, and wait until the checkout is present.
- Headless Linux or VPS: guide the user through Dropbox's headless Linux setup and account-link flow, then wait until
  the repository checkout is present. If headless Dropbox setup is not practical or the user declines it, switch to
  `git` host kind only after explicit confirmation.

After the user confirms Dropbox is installed, linked, and synced, re-run the preflight. Only then run bootstrap when
needed and continue to plan/install.

Do not create a separate Git clone on a target that was selected as `dropbox` unless the user explicitly changes the
host kind to `git`. This avoids two competing public data checkouts on personal machines.

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
platform installer finishes.

### Remote Modes

- `remote-git`: deterministic default for SSH provisioning when the target does not have a Dropbox-backed public data
  checkout. Prepare the target public repository by cloning or fetching it, usually under `~/.local/src/<repo-name>`.
  Use `main` and the latest pushed commit unless instructed otherwise. Require a clean local worktree and a pushed
  commit.
- `remote-dropbox`: use the target public repository that already exists under Dropbox. Local and target Git `HEAD` do
  not need to match. Runtime state stays under `~/.local/state/tilde` on the target.
- `remote-any`: use the provided target repository path as-is. This is intentionally less deterministic; call out
  branch, `HEAD`, and dirty-state uncertainty and continue only with explicit confirmation.

In all remote modes, resolve links, copies, and home inspections against the target machine's home directory and target
repository copies, not the local orchestrating repository. Write deployment state on the target first. The controller may
copy or summarize the target state into its read-only remote mirror before finishing.
