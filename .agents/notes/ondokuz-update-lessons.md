# Ondokuz Update Lessons

Date: 2026-06-14
Context: `$tilde update ssh:ondokuz` on a `remote-git` Linux host

## Summary

The update completed, but exposed three structural issues in how the Tilde skill and data repositories interact on `remote-git` targets.

## Issues

### 1. Remote Tilde skill was outdated

The target's `~/.agents/skills/tilde` was at `e018af5` (old direct `bin/plan` schema), while the controller expected the new `bin/tilde` router (`f06273f`). The first plan command failed until the skill was recloned from GitHub on the target.

**Recommendation:** Add an explicit skill-version check to the remote update/deploy flow. Before running `bin/tilde plan` on a remote host, verify that `~/.agents/skills/tilde` matches the controller's expected version, or update it with `git fetch origin && git merge --ff-only origin/main` (for the public skill repo) or a fresh clone.

### 2. `home/agents/skills/tilde` symlink conflicts with the real skill installation

The public `agents` module links the whole `skills/` directory to `~/.agents/skills`. Inside that directory, `tilde` is a relative symlink (`../../../tilde`). On `remote-git` hosts this resolves to `~/.local/src/tilde`, which does not exist. During apply, Tilde tried to create `~/.agents/skills/tilde` as a symlink to the repo's symlink, which (combined with a temporary workaround symlink) created a loop and broke the skill.

**Recommendation:** Remove `tilde` from `home/agents/skills/`. The Tilde skill should be installed separately from the data repositories (bootstrap, a `skill:github.com/roktas/tilde` declaration, or manual clone). The `agents` module should only link actual shared agent skills, not the control plane itself.

### 3. `chrome` module runs on headless Linux

The `chrome` module declares only macOS packages but includes a Linux `Install` section guarded by `systemctl get-default != graphical.target`. On the headless ondokuz VPS this guard did not prevent the section from running, and it failed with `notok`.

**Recommendation:** Make the `chrome` module macOS-only, add a `hosts` filter that excludes headless hosts, or move the Linux apt repository setup into the `linux` module under the existing `graphical_host` guard.

## Outstanding item

- `private/codex` module on ondokuz remains `notok` because its `github:Lampese/codex-switcher` package requires `gh auth login`. On `remote-git` hosts with controller-side bundle transport for private repos, target-side GitHub CLI authentication is unavailable by design. Consider excluding the `codex` module from headless/remote-git hosts or using a different transport for that asset.
