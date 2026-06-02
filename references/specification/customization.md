# Tilde Customization

## Data-Layer Instruction Evaluation

Tilde data-layer policy is an ordered instruction stack, not a schema that tries to merge prose. For a command or home
workflow, read applicable `## Tilde` sections in precedence order and concatenate matching instructions from broad to
narrow. Later instructions may refine or override earlier instructions in ordinary agent-instruction terms, but they do
not erase earlier safety constraints unless the control-plane spec explicitly allows it.

Valid `## Tilde` section locations are defined in `references/specification/home.md`. For each applicable Tilde section:

1. Apply free text directly under `## Tilde` to all Tilde commands for that file's scope.
2. Apply `### Command: NAME` only when `NAME` matches the current public command or resolved custom command.
3. Apply `### Layout: PATH` when the current inspection, proposal, or command subject is inside `PATH`, or when layout
   facts for `PATH` are needed for bounded discovery.

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
commands always use their control-plane semantics first and may only be refined by data-layer `Command:` sections.
Data repositories must not define `Command: internal.*`, `.name`, or a built-in public command with replacement
semantics.

## Layout Sections

`Layout:` sections are instruction text scoped to a path, not machine-readable mount tables. The path must be `~` or a
`~`-relative path. More specific layout paths apply after broader paths, so `### Layout: ~/Dropbox` refines
`### Layout: ~` for that subtree. If two same-precedence layout sections conflict, keep both in the instruction stack
and ask a clarification question before taking preference-sensitive or destructive action.

## Invalid Policy

Invalid data-layer policy should be reported as a warning during the command that reads it, not as a hard failure, unless
continuing would make the requested action unsafe or ambiguous. Warn for unknown heading types under `## Tilde`,
invalid layout paths, duplicate same-scope custom command definitions with conflicting instructions, and attempted
`internal.*` definitions. Ignore invalid policy for read-only summaries when it is not relevant to the summary.
