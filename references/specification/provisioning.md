# Tilde Provisioning

## Provisioning

Provisioning is the lower-level module operation performed during deployment. It is intended to be idempotent where
practical, but it is not perfectly idempotent.

### Modes

- `apply`: apply repository desired state to the target host. This covers first provisioning and normal state/`HEAD`
  reconciliation, including new links, copies, packages, and selected special sections.
- `refresh`: update only managed external resources: active plan packages and `README.md` `Update` sections. It may run
  even when `HEAD` is unchanged.
- `repair`: retry modules marked `notok` in deployment state at the same `HEAD`.
- `upgrade`: broad package-manager upgrade mode. It may affect packages outside the managed set and runs only on
  explicit user request after scope is described.

`apply` and `repair` are deployment-state/`HEAD` driven. `refresh` and `upgrade` are external-resource/time driven.
The user-facing `update` command runs the `apply` and `refresh` phases in that order, after confirmation, so new desired
state and existing managed external resources can both be brought current.

### Init

- Read current deployment state. Missing deployment state means a fresh install.
- Compare repository `HEAD` with deployment state `head`.
- Identify changes that require provisioning. Frontmatter changes usually matter; changes to already-linked module files
  usually do not require relinking.
- Process changed or required modules.

### Traverse

- Plan core managed links first.
- Process the active platform module first.
- Process the active platform variant second, when present.
- Process active other root modules alphabetically.
- Enter each module directory, read `README.md`, load frontmatter, and merge `all` with the active platform scope.
- Interpret `HEAD`/deployment-state differences to produce the active provisioning set. Added packages, added links,
  removed links, and added copies matter. Removed packages and removed copies are not automatic removal actions.
- In `apply`, run install and link phases.
- In `refresh`, refresh packages and selected `Update` sections in managed scope only.
- In `repair`, retry `notok` modules at the same `HEAD`.
- In `upgrade`, run broad package-manager updates only after explicit confirmation.
- Save deployment state.

### Ordering

- The active platform module runs first.
- The active platform variant runs immediately after the platform module.
- Other root modules run alphabetically by directory name. `misc` has no special position.
- A future `order` frontmatter key may be interpreted as numeric weight. Modules without `order` use the default weight;
  ties keep alphabetical order.

### Install

- Run `Preinstall` instructions when present.
- Install added packages from the active provisioning set, grouped by package type. Do not remove packages removed from
  frontmatter.
- Run `Install` and `Postinstall` instructions when present.

### Link

- Run `Prelink` or `Presetup` instructions when present.
- Create added symlinks.
- Create added copies.
- Remove a dropped link only if the target is a symlink into the active data repository or a dangling symlink. Do not
  touch dropped link targets that are not symlinks or point outside the active data repository.
- Do not automatically remove dropped copy targets.
- Run `Link`, `Postlink`, or `Setup` instructions when present.

### Update

- Run `Update` instructions only in `refresh` or explicitly requested `upgrade`. Do not run them during normal `apply`.
