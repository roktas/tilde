# Tilde Model

## Terms

- **Module**: a root directory that represents one application or provisioning unit.
- **Misc module**: the normal `misc` module for small shared declarations that do not deserve a focused module. It has
  no bootstrap role. If `misc-` exists, it is an `extra` module.
- **Platform module**: `linux`, `macos`, or `windows`. It defines generic platform behavior such as package-manager
  policy or platform defaults.
- **Platform variant**: `linux-`, `macos-`, or `windows-`. The active variant runs immediately after the active platform
  module. The trailing dash has no global meaning; the module README defines the local semantics.
- **Control plane**: the installed `tilde` skill, normally at `~/.agents/skills/tilde`. It owns prompt semantics,
  protocol references, helper commands, fallback home-entrypoint templates, diagnostics, and validation.
- **Public data repository**: the user's public data repository. It contains public-safe modules, shared agent assets,
  and desired state declarations.
- **Private data repository**: the optional private companion repository. It contains private modules, private policy,
  and preference-sensitive home behavior.
- **Host**: the short name derived from `hostname -f` by removing the trailing domain. For example, `kant.local` becomes
  `kant`.
- **Home**: the target user's home directory on the machine being managed. After deployment, Tilde's main user-facing
  surface is the home directory, not the repository checkout.
- **Home entrypoint**: the `~/AGENTS.md` file whose scope is the user's home directory. In steady state it is normally
  linked from the private data repository's `home/AGENTS.md`, or from the public data repository's `home/AGENTS.md`
  when no private data repository is configured. The installed skill provides `assets/AGENTS.md` only as a first-run
  fallback template.
- **Deployment**: applying Tilde's desired state to a local or remote host. Deployment is the user-facing operation that
  may include initialization, bootstrap/preflight, repository preparation, planning, installing links/copies/packages,
  and state update.
- **Provisioning**: the lower-level module operation performed during deployment: evaluating module frontmatter and
  README instructions, then installing packages and creating links or copies.
- **Managed surface**: files, directories, links, copies, packages, and deployment state that Tilde can explain from its
  active public/private repository definitions.
- **Proposal**: an agent-produced plan for a home-management action. A proposal describes intended reads, writes, moves,
  links, copies, or removals before any action is taken.
- **Deployment state**: runtime record for a host. Deployment state records module deployment results; home-management
  proposals are not written to deployment state.

## Model

- The installed skill is the control plane. User-specific home data and host runtime state do not live in the installed
  skill.
- Public and private data repositories declare their Tilde role in existing repository-facing files, preferably
  `AGENTS.md` YAML frontmatter:

  ```yaml
  ---
  tilde:
    protocol: tilde/v1
    role: public
    private: ../PRIVATE_REPO
  ---
  ```

  ```yaml
  ---
  tilde:
    protocol: tilde/v1
    role: private
    public: ../PUBLIC_REPO
  ---
  ```

- Repository directory names are conventions only. Correctness comes from explicit repository identity and bounded
  discovery.
- Each module describes how to install or configure one application or virtual provisioning unit.
- Module names usually match the common application name and default package name. Exceptions belong in the module
  `README.md`.
- A module directory contains `README.md` and any files used during provisioning. README frontmatter is optional.
- Root modules are direct child directories of the active public/private data repository roots. Dot directories, `.git`,
  and `.agents` are excluded.
- A root directory is a module only when it contains `README.md`.
- Provisioning decisions are made after host deployment state is loaded.
- On fresh or underprovisioned hosts, run `bin/bootstrap` explicitly before normal provisioning when
  baseline tools are missing. Bootstrap is state-free and idempotent.
- Deployment uses provisioning modes internally. User-facing commands may say `deploy`, while lower-level module
  execution may use `apply`, `refresh`, `repair`, or `upgrade`.
- Normal plans process the active platform module first, the active platform variant second, and all other active root
  modules alphabetically. Inactive platform modules and inactive platform variants are excluded.
- Root modules may be platform-gated by defining only platform keys such as `linux:`.
- Deployment state for a host is written under `~/.local/state/tilde` by default.

## Paths

- In tracked repository files, write home paths with `~`; do not write expanded home paths.
- Use repository-relative or module-relative paths for files inside the active data repository or installed skill.
- Do not add machine-specific, user-specific, or local checkout-specific absolute filesystem paths to frontmatter,
  instructions, specs, notes, or scripts.


## Deployment State

Machine-specific runtime state lives outside the installed skill and outside the public/private data repositories by
default.

Deployment state is an optimization and provenance cache, not the source of desired state. If host deployment state is
missing, `apply` and the install phase of `update` must treat the host as fresh and rely on idempotent handlers. This
may be slower and noisier, but it must not be semantically destructive.

Preferred state root:

```text
~/.local/state/tilde
```

Suggested structure:

```text
~/.local/state/tilde/
  config.yml
  hosts/
    HOST/
      state.md
      last-plan.json
      last-apply.json
  remotes/
    HOST/
      state.md
```

`config.yml` records the local binding between the installed skill and the user's data repositories:

```yaml
protocol: tilde/v1
skill: ~/.agents/skills/tilde
public: ~/src/PUBLIC_REPO
private: ~/src/PRIVATE_REPO
```

`private` may be omitted when the user has no private companion repository.

Host state frontmatter records enough provenance to explain what was applied:

- `host`: short host name.
- `date`: provisioning time.
- `bootstrap`: bootstrap baseline status when it has been checked or installed.
- `skill`: installed skill path or version.
- `head`: public repository `HEAD` at provisioning time, retained for compatibility with current plan helpers.
- `public`: public repository path and commit.
- `private`: private repository path and commit when present.
- `done`: ordered map of provisioned module directories. Values are `ok`, `notok`, or `ignored`.

The deployment state body is optional. Use it for details that may help resolve future `notok` modules.

The `bootstrap` frontmatter entry records the last known bootstrap baseline result for the host. It uses schema
`tilde.bootstrap/v1`, has a `status` such as `ok`, records the platform and requirements hash used by
`bin/bootstrap --check`, and may record resolved tool paths for `brew`, `ruby`, `git`, and `curl`. This entry is a fast
path cache for bootstrap checks, not desired state. If it is missing, stale, or incompatible with current bootstrap
requirements, `bin/bootstrap --check` must perform a live probe.

`last-plan.json` and `last-apply.json` are read-only status caches after provisioning. `status` may summarize managed
module, link, copy, and package counts from these files without regenerating a plan or checking live targets. If these
cache files are missing, `status` must say that managed-surface counts are unavailable instead of silently performing a
longer discovery pass.

For remote deployments, the target host's state under its own `~/.local/state/tilde` is authoritative. The controller
machine may keep a read-only mirror for status and history under `~/.local/state/tilde/remotes/HOST/`, but remote state
is not owned by the public/private data repositories.

Repository-local `.agents/state/` remains appropriate for local task state, checkpoints, logs, and development scratch.
It must not become the canonical deployment state for a user's host.

## Skill Installation and Updates

Tilde itself is installed and updated as a skill. External package-manager distribution is out of scope for this
specification.

There are three lifecycle modes:

- **Bootstrap**: an external path installs enough agent runtime and Tilde skill to run `$tilde create`, `$tilde init`,
  or `$tilde deploy`.
- **Managed steady state**: the user's public/private home configuration keeps the installed Tilde skill current.
- **Development/local-current**: Tilde is already present on the machine, usually from a local checkout, and must not be
  reinstalled, downgraded, or self-updated unless the user explicitly asks for it.

Managing the Tilde skill must not create a bootstrapping loop. Deployment may require the skill to exist before public
and private data repositories have been installed.

The preferred managed form is a normal package entry in a home data module:

```yaml
---
all:
  packages:
    - skill:github.com/roktas/tilde
---
```

Local development may use ordinary links instead:

```yaml
---
all:
  links:
    ../tilde: ~/.agents/skills/tilde
---
```

Do not grow `skill:` into a broad skill-management schema. If a user needs different behavior for the Tilde skill, put
those instructions in the owning module's `README.md` body and let normal module special-section semantics handle it.
