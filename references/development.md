# Tilde Repository Development

Load this reference when editing this repository, the Tilde skill, helper scripts, module metadata, or validation docs.

## Canonical Files

- Repository instructions: `AGENTS.md`
- Home router template: `assets/AGENTS.md`
- Public data repo shared user-wide instructions module: `../home/agents/AGENTS.md` when present
- Durable provisioning spec: `references/spec.md`
- Spec alias: `.agents/specs/tilde.md`
- Tilde skill: `SKILL.md`
- Plan helper: `bin/plan`
- Bootstrap helper: `bin/bootstrap`
- Provisioning state: `~/.local/state/tilde/hosts/HOST/state.md`
- Agent resume checkpoint: `.agents/state/checkpoints/assistant.md`
- Shared notes and TODO inbox: `.agents/notes/todo.md`
- Local task state: `.agents/state/tasks/`

Keep Tilde design drafts and next-spec working notes under `.agents/notes/`. Promote durable decisions into
`.agents/specs/` or the canonical Tilde spec when they become project truth.

Read the spec before changing provisioning behavior. Read the relevant language skill before editing helper code or
fenced code examples.

## Session Drift

At session start, compare `.agents/state/checkpoints/assistant.md` with the current branch, `HEAD`, and worktree state
when the checkpoint exists. If `HEAD` or dirty state changed since the checkpoint, inspect the drift and summarize it
before editing.

During this drift check, reread current canonical skill, spec, and instruction files before applying conventions
remembered from an earlier session. Treat the repository version as authoritative. At session closeout, refresh the
checkpoint after requested commits or pushes when practical.

## Conventions

- Keep `AGENTS.md` as short repository-local instructions. Keep `assets/AGENTS.md` as the
  canonical home router template. The plan helper owns the `~/AGENTS.md` core managed link; do not put that link in the
  `agents` module. Move durable behavior into the spec, reusable workflow into the skill, and development policy into
  this reference.
- When changing Tilde prompt commands, help behavior, or command semantics in `SKILL.md` or the spec, update the
  user-facing command table and examples in `README.md` when they are affected.
- Root modules must have `README.md`; YAML frontmatter is optional when a module has no explicit provisioning config.
- Follow the spec for module semantics: levels, platform modules, dash variants, `links`, `copies`, `packages`, special
  sections, install/update behavior, and guarded GUI or desktop-host commands.
- `misc` is a normal provisioning module for small shared declarations that do not deserve a focused module. If
  `misc-` exists, it must be `extra`.
- Prefer short contextual file, directory, and helper names. Avoid encoding implementation details in names unless they
  disambiguate real siblings or are part of an established external interface.
- In the public home data repository, `agents` is the shared agent module. `codex` and `opencode` are agent-specific
  modules. Keep agent-specific modules equivalent in feature set when practical; the intended difference is tone and
  weight.
- Do not add expanded home paths or machine-specific absolute filesystem paths to tracked repository files. Write home
  paths with `~`, for example `~/.config/foo`, and otherwise use repository-relative or module-relative paths.
- Do not migrate old `install.sh` files by default. Prefer README frontmatter and special sections; keep a script only
  when it is an intentional module implementation detail.
- When searching for literal text that may contain shell metacharacters such as backticks, `$`, `!`, or quotes, avoid
  double-quoted shell patterns. Prefer `rg -F -e 'literal text'`.

## Validation

Run relevant checks after Tilde skill, helper, or migrated module changes:

```bash
bin/plan --repo ../home --allow-dirty --platform linux --host smoke --format markdown
REPO_ROOT=../home .agents/tests/provision/smoke.sh
RUBOCOP_SERVER=false RUBOCOP_CACHE_ROOT=/tmp/rubocop-cache rubocop --cache false --config .agents/tests/provision/rubocop.yml bin/plan
mapfile -t shell_files < <(rg --hidden -l '^#!.*(bash|sh)' -g '!**/.git/**' -g '!**/.agents/state/**')
shellcheck "${shell_files[@]}"
```

Use Lima with the external `"there"` helper for end-to-end smoke tests. See `testing.md`.

This repository's `.envrc` may put a neighboring `there` checkout ahead of the packaged `"there"` command. In
non-interactive tool shells, direnv may not be loaded automatically; use `direnv exec . COMMAND` when validating
commands that depend on `.envrc`.

Lima:

```bash
bin/smoke
bin/smoke boot
bin/smoke stop
```
