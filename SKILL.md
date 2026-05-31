---
name: tilde
description: Use for Tilde deployment, provisioning, and home-management work. Trigger for `$tilde ...`, `~ ...`, messages whose first word is `tilde`, or requests to create, initialize, deploy, update, diagnose managed state, adopt app/config files, or work with Tilde home behavior.
---

# Tilde

This skill is standalone. Treat `references/spec.md` as the canonical behavior spec. In this repository,
`.agents/specs/tilde.md` may exist as a relative symlink for discoverability; do not treat that alias as a second source
of truth.

Read only the relevant spec sections before changing behavior or executing commands. Keep `SKILL.md` short; durable
semantics belong in `references/spec.md`, and runnable helpers belong in `bin/`.

## Spec Map

Use these links to load the narrowest useful part of the spec:

- Command parsing and confirmation: [Commands](references/spec.md#commands) and
  [User Interaction](references/spec.md#user-interaction).
- Home entrypoint, data-layer customization, discovery, and adoption:
  [Data Repository Tilde Sections](references/spec.md#data-repository-tilde-sections),
  [Home Router](references/spec.md#home-router), [Core Managed Links](references/spec.md#core-managed-links),
  [Bounded Discovery](references/spec.md#bounded-discovery), and [Adoption](references/spec.md#adoption).
- Fresh-host, Dropbox, and remote setup: [Deployment](references/spec.md#deployment),
  [Dropbox Preflight](references/spec.md#dropbox-preflight), [Bootstrap](references/spec.md#bootstrap), and
  [Remote Modes](references/spec.md#remote-modes).
- Module semantics and plan/install behavior: [Module README](references/spec.md#module-readme),
  [Deployment State](references/spec.md#deployment-state), and [Provisioning](references/spec.md#provisioning).
- Tilde skill lifecycle: [Skill Installation and Updates](references/spec.md#skill-installation-and-updates).
- Package work: [Package Installation](references/spec.md#package-installation) and
  [Package Updates](references/spec.md#package-updates).
- Repository development: [Tilde Repository Development](references/development.md).

## Prompt Contract

Treat `$tilde [command] [subject...] [qualifiers...]`, `tilde`-prefixed, and `~`-prefixed (second word is a known
public or internal tilde command) messages as compact natural-language commands, not strict shell invocations. `~`
followed by a path (e.g. `~/.config`) is not a command. Interpret each command by its spec semantics, and do not
introduce a separate command-scope model.

Bare `$tilde` means `help`. It is read-only and must behave like `$tilde help`.

`$tilde help` prints the public command inventory as a GitHub-flavored Markdown table with `Command` and `Action`
columns, then shows the general prompt format, detailed-help form, and bare-command default. `$tilde help COMMAND`
shows only that public command. If `COMMAND` is unknown or internal, say so and then show the public command table.
Prefer `bin/help --format markdown` when available for bare `$tilde` and `$tilde help`. Present the output as rendered Markdown (GFM table, etc.), not as raw code-block text.

Use proposal-first behavior for writes, moves, removals, repository edits, package changes, and remote-host actions.
Prefer structured confirmation and choice UI over raw prompts such as `[Y/n]`. In Codex, use available structured
user-input or AFALA-style interaction; in other agents, use the closest native equivalent. If only text is available,
present explicit choices with target, effect, and blast radius.

## Commands

- `help`: show public commands or one public command's usage.
- `create`: create public/private home repository skeletons.
- `init`: register existing public/private repositories on this host.
- `deploy`: prepare a local or remote host and install desired state.
- `update`: run the normal returning-user maintenance flow.
- `repair`: retry failed install phases from recorded state.
- `upgrade`: run broad package-manager upgrades after explicit confirmation.
- `status`: show a short read-only deployment, home-router, and managed-surface summary. Keep it fast and state-first:
  prefer `bin/status --format markdown` when available; do not regenerate plans, validate live links, query package
  managers, or call Dropbox by default. If full deployment state or caches are missing, warn that status is partial and
  suggest explicit `$tilde status discover`, `$tilde doctor`, or `$tilde deploy`.
- `doctor`: run bounded diagnostics; this is not a whole-home audit.
- `adopt`: inspect the requested app, config, package, or path and propose public `home` or private `home-` placement.
- `clean`, `organize`: preference-sensitive home commands; read `home-/AGENTS.md` when present and otherwise stay
  conservative. `clean` may include duplicate candidates; `organize` may include archive moves.

Internal semantic commands live under `internal.` with `.name` shorthand during Tilde development. Do not show them in
ordinary help. Treat `plan` and `dry-run` as qualifiers on public commands, not as public commands.

## Discovery

After deployment, home commands may start from `~`. Resolve the installed Tilde skill through the `~/AGENTS.md` symlink
target chain when possible, normally `~/.agents/skills/tilde/assets/AGENTS.md`; walk upward from that target until
finding this skill and its spec. Resolve public/private home repositories from local Tilde state, router metadata, the
current repository, or explicit user-provided paths. Never search all of home just to find the repo.

Do not recursively scan `$HOME` by default. No `find $HOME`, `fd $HOME`, or equivalent broad search unless the user
explicitly requests it after scope and cost are described. Use bounded discovery from modules, explicit paths, managed
targets, cheap XDG/home metadata, relevant app/config locations, and cheap package/app metadata.

## Deployment

Choose host kind from the target repo copy: `dropbox`, `git`, `self`, or `any`. For `dropbox`, Dropbox setup and account
linking are interactive preconditions; guide the user, then rerun preflight. Do not create a Git clone on a `dropbox`
target unless the user changes host kind.

For real local deployment or `remote-git`, require a clean worktree and pushed target commit. Generate plans with
`bin/plan`; it never applies changes. Write deployment state on the target first and optionally mirror it back to the
controller. Run `bin/bootstrap` only as the explicit state-free bootstrap prelude.
