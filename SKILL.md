---
name: tilde
description: Use for Tilde deployment, provisioning, and home-management work. Trigger for `$tilde ...`, messages whose first word is `tilde`, or requests to deploy, bootstrap, help, plan, apply, refresh, repair, upgrade, diagnose, inspect links, adopt app/config files, or work with Tilde home behavior.
---

# Tilde

This skill is standalone. Treat `references/spec.md` as the canonical behavior spec. In this repository,
`.agents/specs/tilde.md` may exist as a relative symlink for discoverability; do not treat that alias as a second source
of truth.

Read only the relevant spec sections before changing behavior or executing commands. Keep `SKILL.md` short; durable
semantics belong in `references/spec.md`, and runnable helpers belong in `bin/`.

## Spec Map

Use these links to load the narrowest useful part of the spec:

- Command parsing and confirmation: [Command Semantics](references/spec.md#command-semantics) and
  [User Interaction](references/spec.md#user-interaction).
- Home entrypoint, discovery, and adoption: [Home Router](references/spec.md#home-router),
  [Core Managed Links](references/spec.md#core-managed-links), [Bounded Discovery](references/spec.md#bounded-discovery),
  and [Adoption](references/spec.md#adoption).
- Fresh-host, Dropbox, and remote setup: [Deployment](references/spec.md#deployment),
  [Dropbox Preflight](references/spec.md#dropbox-preflight), [Bootstrap](references/spec.md#bootstrap), and
  [Remote Modes](references/spec.md#remote-modes).
- Module semantics and plan/apply behavior: [Module README](references/spec.md#module-readme),
  [Deployment State](references/spec.md#deployment-state), and [Provisioning](references/spec.md#provisioning).
- Package work: [Package Installation](references/spec.md#package-installation) and
  [Package Updates](references/spec.md#package-updates).
- Repository development: [Tilde Repository Development](references/development.md).

## Prompt Contract

Treat `$tilde [command] [subject...] [qualifiers...]` and first-word `tilde` messages as compact natural-language
commands, not strict shell invocations. Interpret each command by its spec semantics, and do not introduce a separate
command-scope model.

Bare `$tilde` means `update`: reconcile desired state with the live home, then refresh managed external resources after
showing the planned phases and getting confirmation.

`$tilde help` lists all commands with one-line action descriptions, then shows the general prompt format, detailed-help
form, and bare-command default. `$tilde help COMMAND` shows only that command. If `COMMAND` is unknown, say so and then
show the full command list.

Use proposal-first behavior for writes, moves, removals, repository edits, package changes, and remote-host actions.
Prefer structured confirmation and choice UI over raw prompts such as `[Y/n]`. In Codex, use available structured
user-input or AFALA-style interaction; in other agents, use the closest native equivalent. If only text is available,
present explicit choices with target, effect, and blast radius.

## Commands

- `help`: show all commands or one command's usage.
- `deploy`: prepare a local or remote host and apply desired state.
- `bootstrap`: run or plan the explicit fresh-host prelude.
- `update`: run the normal returning-user maintenance flow, combining lower-level `apply` and `refresh` semantics.
- `plan`, `apply`, `refresh`, `repair`, `upgrade`: lower-level provisioning commands.
- `status`: show a short read-only deployment and home-router summary.
- `doctor`: run bounded diagnostics; this is not a whole-home audit.
- `links`: inspect managed links and copies.
- `adopt`: inspect the requested app, config, package, or path and propose public `home` or private `home-` placement.
- `clean`, `organize`, `archive`, `dedupe`: preference-sensitive home commands; read `home-/AGENTS.md` when present and
  otherwise stay conservative.

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
`bin/plan`; it never applies changes. Write deployment state on the target first and copy it back when the target is not
Dropbox-synced. Run `bin/bootstrap` only as the explicit state-free bootstrap prelude.
