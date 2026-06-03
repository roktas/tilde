---
name: tilde
description: Use for Tilde deployment, provisioning, and home-management work. Trigger for `$tilde ...`, `~ ...`, messages whose first word is `tilde`, or requests to create, initialize, deploy, update, diagnose managed state, adopt app/config files, or work with Tilde home behavior.
---

# Tilde

This skill is standalone. Treat `references/specification.md` as the canonical specification entrypoint. It contains the
always-read contract and routes to narrower files under `references/specification/`. In this repository,
`.agents/specs/tilde.md` may exist as a relative symlink for discoverability; do not treat that alias as a second source
of truth.

Read `references/specification.md` first, then only the relevant routed specification file before changing behavior or
executing nontrivial commands. Keep `SKILL.md` short; durable semantics belong in `references/specification.md` and
`references/specification/`, and runnable helpers belong in `bin/`.

## Specification Map

Read [Specification](references/specification.md) first, then load the narrowest routed file:

- Command parsing and confirmation: [Commands](references/specification/commands.md).
- Home entrypoint, data-repository policy sections, discovery, and adoption: [Home](references/specification/home.md).
- Data-layer instruction evaluation, custom commands, and layout policy: [Customization](references/specification/customization.md).
- Fresh-host, Dropbox, and remote setup: [Deployment](references/specification/deployment.md).
- Module semantics: [Modules](references/specification/modules.md).
- Model, state, paths, and skill lifecycle: [Model](references/specification/model.md).
- Plan/install behavior: [Provisioning](references/specification/provisioning.md).
- Package work: [Packages](references/specification/packages.md).
- Repository development: [Tilde Repository Development](references/development.md).

## Prompt Contract

Treat `$tilde [command] [subject...] [qualifiers...]`, `tilde`-prefixed, and `~`-prefixed (second word is a known
public or internal tilde command) messages as compact natural-language commands, not strict shell invocations. `~`
followed by a path (e.g. `~/.config`) is not a command. Interpret each command by its specification semantics, and do not
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
- `status`: show a short read-only deployment, home-entrypoint, and managed-surface summary. Keep it fast and state-first:
  prefer `bin/status --format markdown` when available; do not regenerate plans, validate live links, query package
  managers, or call Dropbox by default. If full deployment state or caches are missing, warn that status is partial and
  suggest explicit `$tilde status discover`, `$tilde doctor`, or `$tilde deploy`.
- `doctor`: run bounded diagnostics; this is not a whole-home audit.
- `adopt`: inspect the requested app, config, package, or path and propose public or private data-repository placement.
- `clean`, `organize`: preference-sensitive home commands; read `~/AGENTS.md` and private policy when present and
  otherwise stay conservative. `clean` may include duplicate candidates; `organize` may include archive moves.

Internal semantic commands live under `internal.` with `.name` shorthand during Tilde development. Do not show them in
ordinary help. Treat `plan` and `dry-run` as qualifiers on public commands, not as public commands.

## Discovery

After deployment, home commands may start from `~`. Treat `~/AGENTS.md` as the user's home-directory instructions,
normally linked from the private data repository's `home/AGENTS.md`, or from the public data repository's
`home/AGENTS.md` when no private data repository is configured. Resolve the installed Tilde skill from local Tilde
state, fallback entrypoint frontmatter, the current repository, or explicit user-provided paths. Never search all of
home just to find the repo.

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
