# Tilde Apply

## Purpose

`bin/tilde apply` is the deterministic executor route for a confirmed provisioning plan. The direct `bin/apply` helper
remains available for focused executor use. This executor replaces agent-generated, deployment-specific apply scripts for
normal Tilde provisioning.

The executor is deliberately narrow. It does not discover repositories, regenerate plans, interpret prose, choose
packages, repair declarations, or invent fallbacks. It may perform deterministic package-handler work described by the
confirmed plan, including selecting an unambiguous `github:` release asset. Unexpected or unsupported conditions produce
structured results for the agent or user to resolve. The implementation lives at `libexec/apply`; `bin/apply` is a
focused wrapper through `bin/tilde apply`.

## Interface

The intended command surface is:

```text
bin/tilde apply --plan PLAN.json [--plan PLAN.json ...]
```

Plans must be generated in the target context. Remote orchestration runs the executor on the target and uses target-local
repository paths, home paths, platform facts, and deployment state.

The caller owns proposal-first confirmation. The apply executor must not turn a plan into a broader action than the user
confirmed.

## Executable Plan

An executable plan is immutable input, not a suggestion to rediscover desired state. `bin/tilde plan` must emit:

- a versioned plan schema;
- repository protocol, role, path, branch, commit, and dirty-state facts;
- target host, platform, mode, level, home, and state path;
- a stable plan identifier or content hash;
- one ordered `actions` stream with stable action identifiers;
- fully materialized action arguments and conflict strategy;
- module identifiers qualified by repository role, such as `public/git` or `private/home`.

Human-oriented summaries and grouped link, copy, package, or section lists may remain in the plan, but the executor uses
only the ordered action stream. It must not reconstruct execution order from grouped summaries.

A multi-repository apply accepts at most one plan per repository role. It validates that all plans describe the same
target host, platform, mode, level, home, and state root. Public actions run before private actions unless the executable
plan format later defines an explicit cross-repository order.

## Validation

The executor validates the complete plan set before the first write:

- every plan uses a supported schema;
- plan identifiers and action identifiers are present and unique;
- repository roles are valid and unique;
- target host and platform match the executing target;
- repository commits and dirty-state expectations still match;
- source paths are readable and remain inside their declared repository;
- target paths are valid for the target home;
- every action kind, package type, conflict strategy, and result policy is supported;
- every action and package condition is supported, and mirrored condition values agree;
- action dependencies refer to known earlier actions;
- state root paths are valid and writable before cache or deployment state writes.

Validation failure blocks the entire apply without changing managed targets or deployment state.

Before reading resume state or writing caches, the executor creates the target host state directory under the validated
state root when it does not already exist. A clean state root with no `hosts/HOST` directory is valid first-apply input.

## Actions

The executor supports these action kinds:

- `entrypoint`: write an approved fallback home entrypoint.
- `package`: install or refresh one exact package declaration through a supported package handler.
- `section`: execute one exact Bash-only special-section block.
- `link`: create or replace one symbolic link using a fully materialized link value.
- `copy`: create or replace one physical copy.
- `manual`: record a confirmed but non-automatable instruction for user follow-up.

The planner owns action order and dependencies. The executor processes actions in plan order.

Special-section Markdown prose is documentation. The executor runs only sections whose plan representation marks them
Bash-only, meaning the section contains shell fenced blocks and no non-shell fenced code blocks. It writes each Bash
block to a temporary script, executes it without rewriting, captures output and exit status, then removes the temporary
script.

Actions that require an interactive terminal or user decision are marked `manual` or `deferred` instead of being
attempted in a non-interactive remote apply. A `manual` action records a `deferred` result with the original instruction
and reason.

If a package handler command is missing, record that package action as `deferred` instead of aborting apply. Deferred
package actions do not fail the module, so later deterministic link/copy actions in the same module can still reconcile
desired state. A present package command that exits nonzero remains `notok`.

For Linux `deb:` package actions, the executor uses non-interactive sudo. If `sudo -n` reports that authentication, a
TTY, or policy approval is required, record the package action as `deferred` with reason `privilege required`; do not
hang waiting for a password prompt. This does not grant privilege or change system policy; it only makes privilege
failure deterministic.

Package commands and Bash-only section blocks run in the Tilde execution environment:

```text
PATH=$TILDE_ROOT/bin:$PATH
TILDE_ROOT=<skill checkout>
TILDE_SUDO=intercept
TILDE_SUDO_LOG=<temporary jsonl path>
```

`bin/sudo` must fail closed outside this environment. Inside the environment it delegates to `bin/tilde sudo`, which
runs the real sudo command with `-n`. A privilege failure emits the stderr marker `TILDE_PRIVILEGE_REQUIRED`, exits with
the reserved status `125`, and appends a `tilde.sudo/v1` JSONL event when `TILDE_SUDO_LOG` is set. Any recorded sudo
event makes the current action `deferred` with reason `privilege required`, even when a shell block exits 0 after
swallowing the sudo failure.

Package actions may include supported conditions. When a condition is not met, the executor records the action as
`ignored` and does not run the package command. The `graphical` condition is always true on macOS, true on Linux only
when `systemctl get-default` is `graphical.target`, and false elsewhere.

## Determinism

For the same executable plan and equivalent initial managed state, the apply executor must use the same action order,
handlers, arguments, link values, conflict strategies, and result classification.

Determinism does not mean package managers or networks produce identical external versions. It means Tilde does not
silently substitute declarations, select ambiguous assets, infer missing commands, or change strategy during apply.

Examples:

- An invalid `brew:` declaration fails; the executor does not guess a replacement formula.
- An ambiguous or unverifiable `github:` release asset is `notok`; the executor does not install a different asset.
- A missing command required by a special section fails that action; the executor does not install an undeclared
  package.
- An interactive `sudo` step in a remote session is `deferred`; the executor does not hang waiting for input.

## Links And Copies

A link action includes the exact symbolic-link value to write. When source and target are both inside the same
Dropbox-synced tree, the planner must emit an equivalent relative link value so the link remains valid across Linux and
macOS home prefixes. This comparison is by logical Dropbox-relative path, not by literal host path prefix; direct
`~/Dropbox` paths and macOS File Provider paths such as `~/Library/CloudStorage/Dropbox` can refer to the same synced
tree. The executor writes that value exactly and never expands it back to a host-specific absolute path.

If the target is already the desired link or copy, the result is `unchanged`.

Replacing an existing target requires an explicit conflict strategy in the plan. The normal approved replacement
strategy moves the previous target into a timestamped backup directory under the target state root before creating the
new link or copy. The executor does not remove or overwrite an unexpected target without such a strategy.

Copy replacement should use a temporary sibling and rename when practical. Package changes and arbitrary special
sections do not have automatic rollback.

## Failure And Resume

Action results are:

- `ok`: action completed.
- `unchanged`: target already matched desired state.
- `ignored`: action was intentionally excluded by the plan.
- `deferred`: action needs interaction or a decision outside non-interactive apply.
- `notok`: action failed or encountered an unsupported condition.

A core-action failure aborts remaining actions. A module action failure skips later dependent actions in that module but
does not prevent independent later modules from running. The executor never retries with changed arguments or a
different strategy.

`last-apply.json` is written atomically after each action and includes plan identifiers, ordered action results, captured
diagnostics, backups, and whether the run completed. An interrupted apply may resume only the exact same plan set and
must skip only actions already recorded as `ok` or `unchanged`.

For `apply` and `repair` plans, host `state.md` folds action results into repository-qualified module results. A module
is `ok` only when all required actions are `ok`, `unchanged`, or `ignored`; `deferred` and `notok` make the module
`notok` with details in the state body. When an `apply` or `repair` plan skips modules because the current deployment
state already covers them, state writing must preserve the previous module results for those skipped modules. An
actionless apply must not collapse a populated `done` map to `{}`. `align`, `refresh`, and `upgrade` plans write
mode-specific `last-align-*`, `last-refresh-*`, or `last-upgrade-*` caches but must not overwrite deployment `state.md`
or deployment `last-plan.json`/`last-apply.json`. `align` is a partial filesystem reconciliation, while refresh and
upgrade are external-resource runs; none of them is a full desired-state deployment record.

`last-plan.json` is a combined cache of the confirmed public/private input plans, not another input plan. Its schema
must identify the cache format separately from the executable `tilde.plan/v1` plan schema. `last-apply.json` and host
state represent the same combined public/private deployment. Independent public and private writes must not overwrite
each other's cached plan or apply results. Partial or external-resource caches use the same cache schema and are kept in
mode-specific files such as `last-align-plan.json`, `last-refresh-plan.json`, and `last-refresh-apply.json`.

When writing host deployment state, apply preserves the previous `bootstrap` frontmatter entry if one exists. Desired
state deployment must not erase the bootstrap baseline cache.

## Non-Goals

The first executor does not:

- perform SSH orchestration, Dropbox setup, or repository discovery;
- regenerate or modify plans;
- parse ordinary README prose into commands;
- provide full rollback for packages or special sections;
- resolve ambiguous package or release metadata;
- repair dirty repositories or unexpected target content;
- run broad package-manager upgrades unless the confirmed plan explicitly uses upgrade mode. Upgrade mode includes the
  full managed update path first, then the broad package-manager actions.

## Acceptance

Implementation is ready for normal deployment integration when:

- a local and remote-dropbox smoke deployment can run without an agent-generated apply script;
- full-plan validation occurs before writes;
- public/private module identities and caches do not collide;
- link, copy, backup, package, Bash-only section, manual, failure, interruption, and resume behavior have fixtures;
- Dropbox-internal links are relative and remain valid under different Linux and macOS home prefixes;
- unsupported and interactive cases produce structured `deferred` or `notok` results without hanging;
- status can summarize the combined cached plan and apply result without regenerating a plan.
