---
tilde:
  protocol: tilde/v1
  source: ~/.agents/skills/tilde/assets/AGENTS.md
---

# Home Agent Instructions

Scope: this file applies to agent work in the user's home directory.

This is a generated fallback. For version-tracked home instructions, manage `~/AGENTS.md` from
the private data repository's `home/AGENTS.md`, or from the public data repository's `home/AGENTS.md` when no private
data repository is configured.

## Routing

- Read `~/.agents/AGENTS.md` when available; more specific instructions win.
- Treat `~` as the managed home workspace.
- Resolve the installed Tilde skill from `tilde.source`; then read its `SKILL.md` and specification.
- Resolve public/private repositories from local Tilde state, home-entrypoint metadata, current repository, or explicit
  paths.
- Read home-scope policy before preference-sensitive commands, avoid broad home scans, and require confirmation before
  destructive actions, repository writes, package changes, or remote-host changes.
