# Tilde Home Entrypoint

## Home Entrypoint

Home entrypoint behavior covers `~/AGENTS.md`, bounded discovery from home, adoption, and preference-sensitive
home-management workflows.

### Home Policy Sections

Data repositories may provide home policy and command customization in existing Markdown bodies. Tilde treats these
sections as data-layer policy and instructions, not as control-plane specification.

Valid locations for home-scope customization:

- `home/AGENTS.md` in the private data repository;
- `home/AGENTS.md` in the public data repository, when no private data repository is configured;
- host `hosts/HOST/README.md` files in public and private data repositories for host-specific policy;
- module `README.md` files for module-local policy.

Root `AGENTS.md` files in public and private data repositories are repository-scope instructions and repository identity
files. Keep target-home layout and preference policy in the home entrypoint source above, not in data-repository root
`AGENTS.md` files. Root `README.md` files remain human-facing overviews unless a future spec explicitly says otherwise.

Use these second-level sections:

- `## Operations`: command-specific policy. Third-level headings are public command names such as `### adopt`,
  `### clean`, and `### deploy`, or custom command names such as `### custom.sync-host`. Data repositories must not
  define or override `internal.*` commands.
- `## Layout`: home or workspace layout facts for bounded discovery and preference-sensitive commands. Use third-level
  headings for specific paths when useful, such as ``### `~/Dropbox` ``. Free text and lists directly under `## Layout`
  apply to that file's scope.

Free text outside these sections remains ordinary agent instruction text. It may still apply to Tilde work through the
normal instruction stack, but it is not command-specific data-layer customization.

Example:

```markdown
## Layout

Use runtime XDG user dirs for localized desktop directories. Do not infer aggressive cleanup rules from public data.

### `~/Dropbox`

Source checkouts live directly under `~/Dropbox`; the old `~/Dropbox/src` layout is a legacy fallback.

## Operations

### adopt

Secrets, credentials, license files, host-specific values, private endpoints, account identifiers, and uncertain private
material belong in the private data repository by default.

### custom.sync-host

Synchronize the matching host directory in the private data repository with `~/.<host>` on the remote machine. Use the
private sync skill. Never delete remote files by default.
```

Home policy precedence is:

```text
control-plane spec
< public home entrypoint source home/AGENTS.md
< private home entrypoint source home/AGENTS.md
< host hosts/HOST/README.md
< module README.md
< explicit user request
```

More specific layout sections override or refine broader layout instructions for the matching path. Data-layer
customization may add user policy and custom commands, but it must not weaken control-plane safety rules such as
proposal-first writes, bounded discovery, explicit destructive confirmation, and hiding internal commands from ordinary
help.

Detailed evaluation, custom command, layout, and invalid-policy behavior lives in
`references/specification/customization.md`.

### Home Entrypoint

`~/AGENTS.md` is the user's home-directory agent instructions. Its primary scope is the home directory, independent of
Tilde. It is the natural place for home layout facts, cleanup and organization preferences, and `## Operations`
customization.

In steady state, Tilde should manage `~/AGENTS.md` as an ordinary module link from a data repository:

1. Prefer the private data repository's `home/AGENTS.md` when a private data repository is configured.
2. Fall back to the public data repository's `home/AGENTS.md` when no private data repository is configured.

The owning module is conventionally named `home` because it represents the target home directory. It should contain a
short `README.md` with normal module frontmatter, such as:

```yaml
---
all:
  links:
    AGENTS.md: ~/AGENTS.md
---
```

The linked `AGENTS.md` should start with a short scope sentence in neutral agent-instruction language, for example
"Scope: this file applies to agent work in the user's home directory." It may include `## Layout` and `## Operations`
sections for home policy and command customization.

The old routing requirement is a discovery requirement, not a separate file kind. An agent that starts from `~` must be
able to find user-wide instructions, the installed Tilde skill, and the configured public/private data repositories
without recursively scanning the home directory. `~/AGENTS.md` satisfies that requirement as ordinary home-directory
agent instructions: fallback copies may use `tilde.source` to identify the installed skill, while steady-state
data-repository entrypoints can rely on local Tilde state, repository frontmatter, and the bounded discovery order
below.

`assets/AGENTS.md` in the installed skill is only the canonical fallback home entrypoint template. Tilde may generate it
at `~/AGENTS.md` during first-run or when no data-repository home entrypoint source exists yet. The fallback must be
minimal: frontmatter, a scope sentence, enough routing guidance to find the installed skill and data repositories, and a
pointer to the selected data repository's `home/AGENTS.md` for version-tracked home instructions.

Do not place `~/AGENTS.md` in the `agents` module. The `agents` module owns shared `~/.agents` assets; the `home` module
owns the home-directory entrypoint.

If `~/AGENTS.md` is missing, Tilde may propose creating a fallback or linking the available data-repository home
entrypoint. If it is a fallback generated from `assets/AGENTS.md`, Tilde should propose replacing it with the
data-repository `home/AGENTS.md` link once that source exists. If it is a legacy symlink to the installed fallback
template, Tilde should propose replacing it with the data-repository link so edits do not dirty the installed skill
repository. If the file is user-owned and not a managed/generated fallback, never overwrite it without explicit
confirmation.

### Bounded Discovery

Do not recursively scan `$HOME` by default. Do not run `find $HOME`, `fd $HOME`, or equivalent broad recursive searches
unless the user explicitly requests a broad scan after the cost and scope are described.

Repository resolution order:

1. Explicit command arguments or options.
2. The current repository's `AGENTS.md` frontmatter, when it declares a Tilde role.
3. The local Tilde state config at `~/.local/state/tilde/config.yml`.
4. The home entrypoint at `~/AGENTS.md`.
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
discovered from frontmatter or a confirmed sibling path.

With two positional repository arguments, the first is public and the second is private.

Default repository locations are convenience only. Default-location discovery uses the conventional public/private
directory-name pair `home` and `home-`; these names are discovery hints, not repository identity. Prefer:

1. `~/Dropbox/home` and `~/Dropbox/home-` when the direct Dropbox topic layout exists.
2. `~/Dropbox/src/home` and `~/Dropbox/src/home-` as a legacy fallback.
3. `~/.local/src/home` and `~/.local/src/home-` otherwise.

If a default path already exists, Tilde should inspect it for Tilde repository identity before using it. If it does not
exist, `create` or `deploy` may offer to create it after confirmation.

When only the default public path is explicit or found, inspect its frontmatter first. If that does not identify the
private data repository, prefer the default `home-` sibling when it exists and confirms a private role. If the public
repository declares a private companion that is missing, stop for a proposal: create or sync the private repository,
choose an explicit private path, or continue public-only after confirmation.

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
