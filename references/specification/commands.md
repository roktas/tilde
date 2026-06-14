# Tilde Commands

## Commands

Tilde commands are a prompt contract, not a strict shell CLI. Treat `$tilde [command] [subject...] [qualifiers...]` as a
compact way to express intent. The command name is stable; the subject and qualifiers may be natural language. Each
command defines its own semantics, and explicit arguments refine the target.

Bare `$tilde` means `help`. It is read-only and must behave like `$tilde help`.

### Runtime Router

`bin/tilde` is the canonical runtime router for implemented helper behavior. It sets the shared Tilde helper
environment, resolves the skill root, normalizes route aliases, and dispatches to the matching `libexec/` helper. It is
a runtime entrypoint, not a replacement for prompt-level agent orchestration.

Before dispatch, the router normalizes empty, `C`, `POSIX`, `C.UTF-8`, and `C.utf8` locale settings to
`LC_ALL=en_US.UTF-8` and `LANG=en_US.UTF-8`. This keeps Ruby helper encoding behavior UTF-8 based while preserving any
explicit non-C locale selected by the caller.

The router may expose implemented helper routes such as:

- `tilde align`
- `tilde help`
- `tilde status`
- `tilde doctor`
- `tilde plan`
- `tilde apply`
- `tilde bootstrap` and `tilde boot`
- `tilde preflight`
- `tilde checkout`
- `tilde ssh`
- `tilde sudo`

The public prompt commands `adopt`, `clean`, `create`, `deploy`, `init`, `organize`, `repair`, `update`, and `upgrade`
are agent-orchestrated unless a matching runtime route is explicitly defined. If those names are invoked directly
through `bin/tilde` without a matching route, the router must fail clearly instead of pretending to apply the prompt
command.

The router accepts dotted internal aliases for development, such as `tilde .plan` and `tilde internal.plan`, when a
matching runtime route exists. Dotted aliases are not shown in ordinary public help.

Use `bin/tilde COMMAND ...` for runtime helper access. Command implementations live under `libexec/`. `bin/sudo` is a
PATH shim for Tilde-controlled execution only; ordinary help must not present it as a public command.

### Public Commands

`$tilde help` is the read-only public command reference. Start the output by showing the general format,
`$tilde <command> [<arguments>...]`. With no subject, it lists public commands with one-line action descriptions in a
GitHub-flavored Markdown table with `Command` and `Action` columns. With one public command subject, it shows detailed
help for only that command. If the subject is a configured custom data-layer command, use the custom-help behavior below.
If the subject is neither a public Tilde command nor a configured custom command, say that no such Tilde command exists,
then behave like bare `$tilde help`. Agents should prefer the installed `bin/tilde help` runtime route for built-in
public help when available. Custom command help requires reading configured data-layer policy.

Use this public action inventory for help output:

| Command | Action |
| --- | --- |
| `adopt` | Adopt an app, config, package, or path into the public or private data repository. |
| `align` | Reconcile links and copies without bootstrap, packages, or module scripts. |
| `clean` | Propose conservative cleanup, including duplicate candidates when relevant. |
| `create` | Create public/private home repository skeletons. |
| `deploy` | Prepare a host and install desired state. |
| `doctor` | Diagnose deployment, repository, host, home-entrypoint, and managed-link health. |
| `help` | Show public commands or detailed help for one public command. |
| `init` | Register existing public/private repositories on this host. |
| `organize` | Propose organization changes, including archive moves when relevant. |
| `repair` | Retry failed install phases from recorded state. |
| `status` | Show a short deployment, home-entrypoint, and managed-surface summary. |
| `update` | Reconcile desired state, then run the fast update path. |
| `upgrade` | Run `update full`, then broad package-manager upgrades after explicit confirmation. |

After the table, show these short help notes:

- Detailed command help: `$tilde help <command>`
- Bare `$tilde` means `help`.

Then show a short example prompt section with no more than five canonical prompts. Keep examples stable, generic, and
representative of common local deployment, remote deployment, Git-backed VPS deployment, adoption, and dry-run/update
flows.

`apply`, `bootstrap`, `install`, `links`, `plan`, `refresh`, `archive`, and `dedupe` are not public prompt commands. Do
not show internal commands in ordinary help. Use `align` when the user wants only managed links and copies reconciled
without package/bootstrap side effects. Treat `plan`, `dry-run`, and `plan-only` as qualifiers on public commands when
the user asks to see the proposal without applying it.

Custom data-layer commands such as `custom.sync-host` are also excluded from ordinary `$tilde help`. If a user asks for
`$tilde help custom.NAME`, resolve that custom command from configured data-repository `## Operations` sections. If it
exists, show the resolved custom-command instructions and remind the user that writes remain proposal-first. If it does
not exist, say that no such custom Tilde command is configured, then behave like bare `$tilde help`.

Public command semantics:

- `help`: show the public Tilde command reference. Usage: `$tilde help [command]`.
- `create`: create or propose public/private home repository skeletons. With no explicit path, use default-location
  discovery before proposing writes.
- `init`: bind existing public/private repositories to the current host. It writes local config and the home entrypoint
  only after confirmation. It does not provision by itself.
- `deploy`: the main first-run and new-host journey command. It may orchestrate `create`, `init`,
  `internal.bootstrap`/preflight, planning, and `internal.install`, while preserving proposal-first behavior for each
  phase.
- `align`: reconcile managed links and copies from public/private repositories without bootstrap, package installs,
  package refreshes, or module special sections. It is the low-side-effect path for hosts that already have enough
  runtime to plan/apply but lack package managers such as Homebrew. The local runtime route `bin/tilde align` generates
  `--mode align` plans for configured or explicit repositories and applies them through `bin/tilde apply`.
- `update`: run the returning-user maintenance flow after confirmation. Plain `update` means
  `internal.install`, then `internal.refresh` with fast scope. `update full` means `internal.install`, then
  `internal.refresh` with full managed scope.
- `repair`: public wrapper over `internal.repair`.
- `upgrade`: run `update full`, then broad package-manager upgrades only on explicit request after describing scope.
  `upgrade` is the widest update command and may affect packages not declared by Tilde.
- `status`: print a short read-only summary of configured public/private repositories, deployment state, and
  home-entrypoint facts, plus a concise managed-link/copy/package surface summary when cached state is available. It should
  prefer the installed `bin/tilde status` route when available so the agent can produce the summary with one read-only
  command. It must not perform broad diagnostics or regenerate plans by default. When full deployment state or status
  caches are missing, print a limited-status warning and suggest explicit next commands such as
  `$tilde status discover`, `$tilde doctor`, or `$tilde deploy`.
- `doctor`: diagnose host/home health, repository discovery, dirty worktrees, broken managed links, missing state, and
  Dropbox/Git consistency. It reports findings and suggestions, but it is not a whole-home audit. For Dropbox-backed
  managed links, classify findings as active, cache, archive, or tmp so cleanup decisions do not treat disposable or
  archival areas like live desired state.
- `adopt`: inspect a requested app, config, package identity, or explicit path; propose how to move it into the public
  or private data repository; and wait for confirmation before any write.
- `clean`: propose conservative cleanup for selected home content. It may include duplicate candidates when relevant.
- `organize`: propose organization changes for selected home content. It may include archive moves when relevant.

Preference-sensitive commands:

- `clean`
- `organize`

These commands depend on personal policy. Before running them, read `~/AGENTS.md` when available. In steady state that
file should come from the private data repository's `home/AGENTS.md`, or from the public data repository's
`home/AGENTS.md` when no private data repository is configured. If no home-scope policy exists, produce only
conservative proposals or suggest creating home-scope policy; do not infer aggressive cleanup or organization rules from
the public repository root instructions.

If a user asks for `dedupe`, interpret it as a `clean` request focused on duplicate candidates. If a user asks for
`archive`, interpret it as an `organize` request focused on archive moves. If a user asks for `links`, use `align` when
they want to apply managed links/copies, `status` for a read-only managed-surface summary, or `doctor` for
broken/stale/conflicting link diagnostics. If a user asks for `plan`, use the nearest public command with a `dry-run` or
`plan-only` qualifier.

`private` is not a built-in command. Natural-language requests such as "adopt this into private" or "check the private
repo" are valid qualifiers on other commands.

`custom.*` names are data-layer prompt commands. Resolve them according to the data-layer instruction evaluation rules
in `references/specification/customization.md`. They may define user-specific workflows, but they do not replace public
command semantics and do not bypass proposal-first confirmation.

### Fast Status

`status` is state-first and latency-sensitive. Its default path reads only cheap bounded sources:

- local Tilde config at `~/.local/state/tilde/config.yml`;
- host deployment state at `~/.local/state/tilde/hosts/HOST/state.md`;
- cached deployment `last-plan.json` and `last-apply.json` when present;
- cached refresh or upgrade plan/apply files when present;
- configured public/private repository summaries;
- home-entrypoint file and installed-skill facts.

Default `status` must not:

- run `bin/tilde plan` to regenerate desired state;
- read every module `README.md` just to compute managed-surface counts;
- walk all managed targets to validate live links;
- query package managers, Dropbox, network remotes, or SSH targets unless the user explicitly requested that target.

If config, host state, or cache files are missing, return a partial summary and say that full deployment state was not
found. Long read-only fallback discovery is opt-in: use a qualifier such as `$tilde status discover` after telling the
user that Tilde will inspect module metadata and managed targets and may take noticeably longer. Broken-link, stale-link,
package, Dropbox, and consistency diagnostics belong to `doctor`, not default `status`.

### Internal Semantic Commands

Commands in the `internal.` namespace are internal semantic commands. They are not shown by ordinary `$tilde help`, are
not intended as user-facing entrypoints, and may be used by the skill/spec to define higher-level behavior.

For convenience while writing prompt-level specs or during Tilde development, `.name` may be accepted as shorthand for
`internal.name`. The dotted form signals private/internal semantics and leaves room for future namespaces.

Internal commands:

- `internal.bootstrap` or `.bootstrap`: run or plan the fresh-host bootstrap prelude.
- `internal.plan` or `.plan`: generate a provisioning plan.
- `internal.apply` or `.apply`: apply a provisioning plan.
- `internal.align` or `.align`: reconcile managed links and copies only.
- `internal.install` or `.install`: install desired state from public/private data repositories.
- `internal.refresh` or `.refresh`: refresh external resources with an explicit scope. Fast scope runs after
  desired-state link reconciliation and updates normal system package managers; full scope also refreshes managed
  non-system package types and selected `Update` sections.
- `internal.repair` or `.repair`: retry failed modules or failed installation phases from recorded state.
- `internal.ssh` or `.ssh`: run Tilde-controlled remote script delivery.
- `internal.sudo` or `.sudo`: classify Tilde-controlled sudo execution and generate privilege handoff commands.

If a user explicitly requests an internal command, explain that it is internal and suggest the public command that covers
the same workflow, unless the user is developing Tilde itself.

### Command Relationships

```text
deploy = init + internal.bootstrap/preflight + internal.install
align = internal.align
update = internal.install + internal.refresh(scope=fast)
update full = internal.install + internal.refresh(scope=full)
upgrade = update full + broad package-manager upgrade
repair = public wrapper over internal.repair
```

The update commands form an explicit scope ladder: `update < update full < upgrade`. Do not treat plain `update` as a
full managed refresh. Do not treat `update full` as a broad global upgrade. `upgrade` includes `update full` first, then
adds package-manager-wide or aggressive upgrade actions that may go beyond Tilde-managed declarations.

The `dry-run`, `plan`, and `plan-only` qualifiers on public commands use `internal.plan` to produce a proposal and then
stop before applying changes.

Runtime implementations should treat dotted command tokens as command names before path or extension interpretation, or
otherwise provide an unambiguous way to invoke internal commands during development.

### Proposal-First Rules

Repository creation, repository edits, home-entrypoint writes, state writes, package changes, file links, file copies,
remote-host actions, and destructive home-management actions must be proposal-first.

Proposals should name:

- target paths or hosts;
- what will be written, moved, removed, linked, copied, or installed;
- whether public or private data will be touched;
- whether runtime state will be updated;
- the expected blast radius.

### User Interaction

Use the agent runtime's clearest available interaction surface for confirmations, choices, and menus. Prefer native
structured confirmation or choice UI over raw terminal-style prompts such as `[Y/n]` when the runtime provides one. In
Codex, use the available structured user-input or AFALA-style tool when it is available and appropriate; in other agents,
use the equivalent native interaction mechanism when one exists.

If no structured UI is available, ask in plain language with explicit choices. Name the action, target host or path, and
blast radius. For multi-choice decisions, present a short numbered or bulleted list with one recommended option when
there is a safe default. For destructive or preference-sensitive actions, make the opt-in explicit; do not rely on a
single-letter default prompt.

Commands are proposal-first when they may change files, repositories, packages, state, home-entrypoint files, or remote
hosts. A proposal must describe the intended action and wait for confirmation before writes, moves, removals, package
changes, or repository edits.
