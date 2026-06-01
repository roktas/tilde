# Tilde Home Entrypoint

## Home Entrypoint

Home entrypoint behavior covers the home router, bounded discovery from home, adoption, and preference-sensitive
home-management workflows.

### Data Repository Tilde Sections

Data repositories may provide Tilde-specific customization in existing Markdown bodies. The canonical anchor is a
second-level `## Tilde` heading. Tilde treats that section as data-layer policy and instructions, not as control-plane
specification.

Valid locations:

- root `AGENTS.md` in public and private data repositories;
- host `README.md` files for host-specific policy;
- module `README.md` files for module-local policy.

Do not put Tilde-specific data-layer policy in the home router. Root `README.md` files remain human-facing overviews
unless a future spec explicitly says otherwise.

Inside `## Tilde`, use typed third-level headings:

- `### Command: NAME`: instructions for a public command such as `adopt`, `clean`, or `deploy`, or for a custom command
  such as `custom.sync-host`. Data repositories must not define or override `internal.*` commands.
- `### Layout: PATH`: home or workspace layout facts for bounded discovery and preference-sensitive commands. `PATH`
  should be `~` or a `~`-relative path such as `~/Dropbox`.

Free text directly under `## Tilde` applies to all Tilde commands for that file's scope.

Example:

```markdown
## Tilde

### Command: adopt

Secrets, credentials, license files, host-specific values, private endpoints, account identifiers, and uncertain private
material belong in `home-` by default.

### Command: custom.sync-host

Synchronize the matching host directory in `home-` with `~/.<host>` on the remote machine. Use the private sync skill.
Never delete remote files by default.

### Layout: ~

Use runtime XDG user dirs for localized desktop directories. Do not infer aggressive cleanup rules from public data.

### Layout: ~/Dropbox

Source checkouts live under `~/Dropbox/src`.
```

Tilde section precedence is:

```text
control-plane spec
< public data root AGENTS.md
< private data root AGENTS.md
< host README.md
< module README.md
< explicit user request
```

More specific `Layout:` sections override or refine broader layout sections for the matching path. Data-layer
customization may add user policy and custom commands, but it must not weaken control-plane safety rules such as
proposal-first writes, bounded discovery, explicit destructive confirmation, and hiding internal commands from ordinary
help.

### Home Router

`assets/AGENTS.md` in the installed skill is the canonical home router template. Tilde deployment exposes it as
`~/AGENTS.md` through a core managed link or generated short router, outside module frontmatter. Keep the router short.
It routes agents; it does not carry detailed private preferences or full repository development policy.

The router should tell agents to:

- Treat the current directory as the user's home workspace when loaded from `~`.
- Resolve the installed Tilde skill from the resolved symlink target chain of `~/AGENTS.md` when possible. The normal
  target is `~/.agents/skills/tilde/assets/AGENTS.md`.
- Starting at the target file's parent directory, walk ancestors only until finding a directory that contains both
  `SKILL.md` and `references/specification.md`. That directory is the installed Tilde skill.
- Discover configured public/private home repositories from local Tilde state, router metadata, the current repository,
  or explicit paths.
- Discover sibling `home-` from `home` only when repository identity confirms it.
- Avoid recursive home scans by default.
- Read `home-/AGENTS.md` before preference-sensitive home commands when that file exists.
- Require explicit confirmation for destructive actions and for repository writes.

Do not put personal home layout policy in the public router. Layout policy such as localized directory names, cleanup
preferences, archive rules, and organization rules belongs in `home-/AGENTS.md` when private policy exists. Public
behavior may use cheap runtime detection, such as XDG user dirs, but must not assume a personal layout.

### Core Managed Links

Tilde deployment has core managed links that are not owned by any root module. They are planned before modules and use
the same confirmation and application semantics as normal link actions.

Core links:

- installed skill `assets/AGENTS.md` -> `~/AGENTS.md`

Do not place the home router link in the `agents` module. The `agents` module owns shared `~/.agents` assets; the home
router is a Tilde deployment invariant.

### Bounded Discovery

Do not recursively scan `$HOME` by default. Do not run `find $HOME`, `fd $HOME`, or equivalent broad recursive searches
unless the user explicitly requests a broad scan after the cost and scope are described.

Repository resolution order:

1. Explicit command arguments or options.
2. The current repository's `AGENTS.md` frontmatter, when it declares a Tilde role.
3. The local Tilde state config at `~/.local/state/tilde/config.yml`.
4. The home router at `~/AGENTS.md`.
5. Sibling discovery from an identified public or private repository, confirmed by `AGENTS.md` frontmatter.
6. Default location discovery for `create`, `init`, and first-run `deploy` only.
7. A clarification question.

Preferred command option names:

```text
--public PATH
--private PATH
--state-dir PATH
```

Positional convenience is allowed:

```text
$tilde create
$tilde init
$tilde init PUBLIC
$tilde init PUBLIC PRIVATE
```

With no explicit public path, `create` and `init` may use default-location discovery and then present a proposal before
creating or binding anything.

With one positional repository argument, the argument is the public data repository. The private data repository may be
discovered from frontmatter or a confirmed sibling path such as `home-`.

With two positional repository arguments, the first is public and the second is private.

Default repository locations are convenience only:

1. `~/Dropbox/src/home` and `~/Dropbox/src/home-` when `~/Dropbox/src` exists.
2. `~/.local/src/home` and `~/.local/src/home-` otherwise.

If a default path already exists, Tilde should inspect it for Tilde repository identity before using it. If it does not
exist, `create` or `deploy` may offer to create it after confirmation.

Use bounded discovery from:

- Existing public and private modules.
- Explicit paths provided by the user.
- Known managed targets from active module definitions.
- Cheap standard home metadata, such as XDG user dirs.
- Known application/config locations relevant to the requested subject.
- Cheap package or application metadata when available.

`status` is the exception to ordinary bounded-discovery fallback. If status state is incomplete, report the limitation
and stop unless the user explicitly requested a discovery qualifier or a diagnostic command.

Localized subjects such as `downloads`, `indirilenler`, or `İndirilenler` should be resolved through runtime detection
or private policy when possible. Hardcoded names are fallback only.

### Adoption

For `$tilde adopt SUBJECT`, resolve the subject in this order:

1. Existing public or private module.
2. Explicit path when the subject is path-like.
3. Known app data, config, and state locations for the target platform.
4. Cheap package, application, bundle, desktop, or release metadata.
5. A clarification question.

If the module name is not explicit, propose the app name as the default and confirm it before writing. Prefer generic
public/private repository wording; do not bake user-specific repository names into the control-plane spec.

Discovery must include bounded app configuration/state locations. Present discovered files or directories for approval
before adoption. Classify secrets, credentials, license files, host-specific values, private endpoints, account
identifiers, and uncertain private material as private by default.

When adding configuration to a module, drop leading dots from module-relative filenames unless the user explicitly asks
otherwise. Add matching `links` frontmatter in the same edit. Use `links` for stable user-owned config, and `copies` for
files or directories that target applications are expected to overwrite.

Before writing an adoption, inspect dirty state in each target repository. Do not overwrite uncommitted work without
explicit confirmation.

### Home Workflow State

Home-management proposals are not deployment state. Do not write adoption, cleanup, organization, or diagnostic
proposals to `~/.local/state/tilde/hosts/HOST/state.md`.

For broad, risky, multi-file, multi-session, or interrupted home workflows, use `.agents/state/tasks/` as local task
state when useful. Keep durable decisions in the Tilde specification or in reviewed notes, not in deployment state.

### Apply Vocabulary

Follow-up phrases such as `apply`, `apply proposal`, `do it`, or `adopt it` refer to the latest proposal only when the
reference is unambiguous. If there is any ambiguity, summarize the proposal again before asking for confirmation.

With an active unambiguous proposal, `apply` applies that proposal after confirmation. Without an active proposal,
suggest `deploy dry-run`, `deploy`, or `update` as appropriate. Use `internal.apply` only for Tilde development or when
the user explicitly asks for internal command behavior.

If an action partially fails, report what changed, what did not change, and what remains. Do not promise automatic
rollback unless a rollback plan was explicitly prepared.

Remote destructive or preference-sensitive commands require confirmation that names the remote host, target home path,
and action set.
