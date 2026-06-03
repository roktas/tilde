# Tilde Customization

## Data-Layer Instruction Evaluation

Tilde data-layer policy is an ordered instruction stack, not a schema that tries to merge prose. For a command or home
workflow, read applicable `## Layout` and `## Operations` sections in precedence order and concatenate matching
instructions from broad to narrow. Later instructions may refine or override earlier instructions in ordinary
agent-instruction terms, but they do not erase earlier safety constraints unless the control-plane spec explicitly
allows it.

Valid home policy locations are defined in `references/specification/home.md`. For each applicable policy source:

1. Apply ordinary instruction text outside `## Layout` and `## Operations` through the normal agent instruction stack.
2. Apply `## Layout` text when layout facts are needed for bounded discovery or the current subject is inside that
   layout scope.
3. Apply more specific third-level layout headings after broader `## Layout` text when their path matches the current
   subject or needed discovery context.
4. Apply `## Operations` text only for Tilde command workflows.
5. Apply `### NAME` under `## Operations` only when `NAME` matches the current public command or resolved custom
   command.

The home entrypoint source provides target-home policy. Public and private root `AGENTS.md` files provide repository
identity and repository-scope instructions only. Host policy lives in `hosts/HOST/README.md`, where `HOST` is the short
host name used by deployment state. Module-local policy lives in the module's `README.md` and applies only when that
module or one of its managed targets is relevant to the command.

## Custom Commands

Custom command names must be dotted names outside the `internal.` namespace, normally `custom.NAME`. They are invoked
only when the user's command token exactly matches the custom command name, such as `$tilde custom.sync-host`. Custom
commands are data-layer prompt commands: resolve their instructions from the data repositories, present a proposal for
any write, move, removal, package, state, repository, home-entrypoint, or remote-host action, and then wait for explicit
confirmation. A custom command does not automatically bind to a helper script. If it needs a script, the relevant
instructions must name the script or module section to use.

Custom commands are not shown in ordinary `$tilde help`, which remains the stable public command inventory. If a user
asks `$tilde help custom.NAME`, show the resolved custom-command instructions when the command exists in the configured
data repositories; otherwise say that no such custom Tilde command is configured and then show ordinary help. Public
commands always use their control-plane semantics first and may only be refined by matching data-layer operation
sections. Data repositories must not define `internal.*`, `.name`, or a built-in public command with replacement
semantics.

## Layout Sections

`## Layout` sections are instruction text, not machine-readable mount tables. Third-level layout headings may name `~`
or `~`-relative paths, with optional Markdown code formatting such as ``### `~/Dropbox` ``. More specific layout paths
apply after broader paths. If two same-precedence layout sections conflict, keep both in the instruction stack and ask a
clarification question before taking preference-sensitive or destructive action.

## Invalid Policy

Invalid data-layer policy should be reported as a warning during the command that reads it, not as a hard failure, unless
continuing would make the requested action unsafe or ambiguous. Warn for invalid layout paths, duplicate same-scope
custom command definitions with conflicting instructions, and attempted `internal.*` definitions. Ignore invalid policy
for read-only summaries when it is not relevant to the summary.
