# Tilde Repository Development

Load this reference when editing this repository, the Tilde skill, helper scripts, module metadata, or validation docs.

## Canonical Files

- Repository instructions: `AGENTS.md`
- Fallback home entrypoint template: `assets/AGENTS.md`
- Public data repo shared user-wide instructions module: `../home/agents/AGENTS.md` when present
- Durable specification entrypoint: `references/specification.md`
- Routed detailed specifications: `references/specification/`
- Dotagents spec alias: `.agents/specs/tilde.md`
- Tilde skill: `SKILL.md`
- Status helper: `bin/status`
- Plan helper: `bin/plan`
- Bootstrap helper: `bin/bootstrap`
- Checkout preflight helper: `bin/preflight`
- Provisioning state: `~/.local/state/tilde/hosts/HOST/state.md`
- Agent resume checkpoint: `.agents/state/checkpoints/assistant.md`
- Shared notes and TODO inbox: `.agents/notes/todo.md`
- Local task state: `.agents/state/tasks/`

Keep Tilde design drafts and next-specification working notes under `.agents/notes/`. Promote durable decisions into
`.agents/specs/` or the canonical Tilde specification when they become project truth.

Read the specification before changing provisioning behavior. Read the relevant language skill before editing helper
code or fenced code examples.

## Session Drift

At session start, compare `.agents/state/checkpoints/assistant.md` with the current branch, `HEAD`, and worktree state
when the checkpoint exists. If `HEAD` or dirty state changed since the checkpoint, inspect the drift and summarize it
before editing.

During this drift check, reread current canonical skill, specification, and instruction files before applying conventions
remembered from an earlier session. Treat the repository version as authoritative. At session closeout, refresh the
checkpoint after requested commits or pushes when practical.

## Conventions

- Keep `AGENTS.md` as short repository-local instructions. Keep `assets/AGENTS.md` as the first-run fallback home
  entrypoint template. The `home` data module owns the steady-state `~/AGENTS.md` link; do not put that link in the
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
.agents/tests/apply/smoke.sh
.agents/tests/deploy/smoke.sh
REPO_ROOT=../home .agents/tests/provision/smoke.sh
RUBOCOP_SERVER=false RUBOCOP_CACHE_ROOT=.agents/state/rubocop-cache rubocop --cache false --config .agents/tests/provision/rubocop.yml bin/plan bin/apply
mapfile -t shell_files < <(rg --hidden -l '^#!.*(bash|sh)' -g '!**/.git/**' -g '!**/.agents/state/**')
shellcheck "${shell_files[@]}"
```

Use Lima with the external `"there"` helper for end-to-end provisioning tests.

### Lima

The Tilde smoke wrapper expects `"there"` to be available in `PATH`. Install the `there` package, or activate an
environment that provides a compatible `"there"` command.

This skill intentionally does not encode how `"there"` is installed. See the `there` documentation for command behavior
and detailed usage.

This repository's `.envrc` may put a neighboring `there` checkout ahead of the packaged `"there"` command. In
non-interactive tool shells, direnv may not be loaded automatically; use `direnv exec . COMMAND` when validating
commands that depend on `.envrc`.

Run the normal Tilde smoke script inside the Lima instance:

```bash
bin/smoke
```

Run the bootstrap helper inside the Lima instance:

```bash
bin/smoke boot
```

For fast repeated tests, stop the instance instead of destroying it:

```bash
bin/smoke stop
```

For a fresh-host test, destroy the instance explicitly:

```bash
bin/smoke destroy
```

Clean Lima's image cache only when explicitly requested:

```bash
bin/smoke prune
```

### Direct There Commands

Use `"there"` directly when a test needs a custom command:

```bash
there run .agents/tests/provision/smoke.sh
```
