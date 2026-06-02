# Tilde Specification

This file is the canonical Tilde specification entrypoint. Read it on every Tilde task. It intentionally keeps only the
always-loaded contract, routing map, and public command inventory here; detailed behavior lives in the narrower files
under `references/specification/`.

Do not treat the files under `references/specification/` as independent specifications. They are routed parts of this
specification, and this file is the stable entrypoint for skills, repository instructions, and `.agents/specs/tilde.md`.

## Always-Read Contract

- Tilde is an installed agent skill and control plane. User-specific desired state and policy live in separate public
  and private home data repositories.
- Machine runtime state lives outside the skill and data repositories, under `~/.local/state/tilde` by default.
- Public/private repository identity comes from explicit state, explicit paths, or `AGENTS.md` frontmatter declaring
  `tilde.protocol: tilde/v1` and a repository `role`.
- `$tilde`, first-word `tilde`, and command-shaped `~` prompts are compact natural-language commands, not strict shell
  invocations. Bare `$tilde` means read-only `help`.
- Writes, moves, removals, package changes, repository edits, home-entrypoint writes, state writes, and remote-host
  actions are proposal-first and require explicit confirmation.
- Discovery is bounded. Do not recursively scan `$HOME` unless the user explicitly asks after scope and cost are
  described.
- The home entrypoint is `~/AGENTS.md`; it contains home-directory agent instructions and may route agents to the
  installed Tilde skill and configured public/private home repositories.
- Internal semantic commands live under `internal.` with `.name` shorthand for Tilde development. Ordinary help must
  show only public commands.

## Read Map

Read this file first, then load only the narrowest file needed for the work:

| Work | Read |
| --- | --- |
| Terms, roles, paths, state, and skill lifecycle | `references/specification/model.md` |
| Module layout, README frontmatter, links, copies, and special sections | `references/specification/modules.md` |
| Command parsing, help, status, internal commands, and confirmation rules | `references/specification/commands.md` |
| Home entrypoint, data-repository Tilde sections, bounded discovery, and adoption | `references/specification/home.md` |
| Data-layer instruction evaluation, custom commands, layout policy, and invalid policy | `references/specification/customization.md` |
| Fresh-host, create/init/deploy, Dropbox, bootstrap, and SSH/remote modes | `references/specification/deployment.md` |
| Planning, traversal, ordering, install, link, and update behavior | `references/specification/provisioning.md` |
| Package install and managed update semantics | `references/specification/packages.md` |
| Repository development and validation workflow | `references/development.md` |

Before changing behavior or executing nontrivial Tilde work, read the relevant routed file. Do not bulk-read every
reference file unless the task is cross-cutting.

## Public Commands

`$tilde help` must show public commands as a GitHub-flavored Markdown table with `Command` and `Action` columns. The
installed helper `bin/help --format markdown` emits the canonical public table.

| Command | Action |
| --- | --- |
| `adopt` | Adopt an app, config, package, or path into the public or private data repository. |
| `clean` | Propose conservative cleanup, including duplicate candidates when relevant. |
| `create` | Create public/private home repository skeletons. |
| `deploy` | Prepare a host and install desired state. |
| `doctor` | Diagnose deployment, repository, host, home-entrypoint, and managed-link health. |
| `help` | Show public commands or detailed help for one public command. |
| `init` | Register existing public/private repositories on this host. |
| `organize` | Propose organization changes, including archive moves when relevant. |
| `repair` | Retry failed install phases from recorded state. |
| `status` | Show a short deployment, home-entrypoint, and managed-surface summary. |
| `update` | Reconcile desired state, then refresh managed external resources. |
| `upgrade` | Run broad package-manager upgrades after explicit confirmation. |

Detailed public and internal command semantics live in `references/specification/commands.md`.

## Ownership Rules

- `references/specification.md` owns the always-read contract, routing map, and public inventory.
- Files under `references/specification/` own detailed behavior in their routed areas.
- `SKILL.md` owns reusable prompt workflow and should stay short.
- `bin/` owns runnable helper implementations.
- `references/development.md` owns repository-development workflow.

When adding or moving behavior, put it in exactly one detailed specification file and link to it from this entrypoint
when it changes the read map or always-read contract.
