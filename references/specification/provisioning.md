# Tilde Provisioning

## Provisioning

Provisioning is the lower-level module operation performed during deployment. It is intended to be idempotent where
practical, but it is not perfectly idempotent.

Planning and execution are separate. `bin/plan` produces the confirmed executable action stream; `bin/apply` validates
and executes that exact stream according to [Apply](apply.md). Apply must not rediscover desired state or reconstruct
action order from grouped summaries.

### Modes

- `apply`: apply repository desired state to the target host. This covers first provisioning and normal state/`HEAD`
  reconciliation, including new links, copies, packages, and selected special sections.
- `refresh`: update external resources using an explicit scope. Fast scope is the default for plain `update`; it runs
  normal updates for active system package managers after the public `update` flow has reconciled desired state. Full
  scope is selected by `update full`; it also refreshes managed non-system package types and selected `README.md`
  `Update` sections. Refresh may run even when `HEAD` is unchanged.
- `repair`: retry modules marked `notok` in deployment state at the same `HEAD`.
- `upgrade`: broad package-manager upgrade mode. It first includes the full refresh behavior, then runs
  package-manager-wide or aggressive upgrade actions. It may affect packages outside the managed set and runs only on
  explicit user request after scope is described.

`apply` and `repair` are deployment-state/`HEAD` driven. `refresh` and `upgrade` are external-resource/time driven.
The user-facing `update` command runs the `apply` and fast `refresh` phases in that order, after confirmation, so new
desired state and normal system package managers can both be brought current. `update full` uses full refresh scope.
`upgrade` is a superset of `update full`.

### Init

- Read current deployment state. Missing deployment state means a fresh install.
- Compare repository `HEAD` with deployment state `head`.
- Identify changes that require provisioning. Frontmatter changes usually matter; changes to already-linked module files
  usually do not require relinking.
- Process changed or required modules.

### Traverse

- Plan the fallback home entrypoint first, but only when no active or companion data-repository module links
  `~/AGENTS.md`.
- Process the active platform module first.
- Process the active platform variant second, when present.
- Process active other root modules alphabetically.
- Enter each module directory, read `README.md`, load frontmatter, and merge `all` with the active platform scope.
- Interpret `HEAD`/deployment-state differences to produce the active provisioning set. Added packages, added links,
  removed links, and added copies matter. Removed packages and removed copies are not automatic removal actions.
- In `apply`, run install and file/link phases.
- In fast `refresh`, run normal broad updates for active system package managers only.
- In full `refresh`, also refresh managed non-system package declarations and selected `Update` sections.
- In `repair`, retry `notok` modules at the same `HEAD`.
- In `upgrade`, run full refresh first, then broad or aggressive package-manager updates only after explicit
  confirmation.
- Save deployment state.

### Ordering

- The active platform module runs first.
- The active platform variant runs immediately after the platform module.
- Other root modules run alphabetically by directory name. `misc` has no special position.
- A future `order` frontmatter key may be interpreted as numeric weight. Modules without `order` use the default weight;
  ties keep alphabetical order.
- Later module `Install` and `Postinstall` sections may rely on tools provided by earlier modules, especially the
  active platform module and its variant.
- If a later module needs a tool that is not already provided by earlier modules, declare that tool in an earlier
  platform module or move the work into an earlier bootstrap phase instead of hiding the dependency inside the later
  module.

### Install

- Run `Preinstall` instructions when present.
- Install added packages from the active provisioning set, grouped by package type. Do not remove packages removed from
  frontmatter.
- Run `Install` and `Postinstall` instructions when present.

### File And Link

- Run `Prelink` or `Presetup` instructions when present.
- Create or refresh the fallback home entrypoint when approved and no active or companion data-repository module links
  `~/AGENTS.md`.
- Create added symlinks.
- Create added copies.
- Remove a dropped link only if the target is a symlink into the active data repository or a dangling symlink. Do not
  touch dropped link targets that are not symlinks or point outside the active data repository.
- Do not automatically remove dropped copy targets.
- Run `Link`, `Postlink`, or `Setup` instructions when present.

### Update

- Run `Update` instructions only in full `refresh` or explicitly requested `upgrade`. Do not run them during plain
  `update`, fast `refresh`, or normal `apply`.
