# Tilde Home Router

This file is the canonical Tilde home router template. Tilde deployment exposes it as `~/AGENTS.md` through a core
managed link or generated router. Keep it short: it routes agents, but it does not carry detailed private preferences or
full repository development policy.

Read `~/.agents/AGENTS.md` for shared user-wide defaults when available. More specific repository, task, or tool
instructions win.

## Routing

- Treat the current directory as the user's home workspace when this file is loaded from `~`.
- Resolve the installed Tilde skill from the resolved symlink target chain of `~/AGENTS.md` when possible. The normal
  target is `~/.agents/skills/tilde/assets/AGENTS.md`.
- Starting at the target file's parent directory, walk ancestors only until finding a directory that contains both
  `SKILL.md` and `references/spec.md`. That directory is the installed Tilde skill.
- If symlink resolution is unavailable or the target does not identify the installed Tilde skill, use the current skill
  or data repository when already inside one, then an explicit user-provided path. Do not recursively search `~` to find
  repositories.
- In the installed skill, read `SKILL.md`; it points to the canonical spec and supporting references.
- Discover configured public/private home repositories from local Tilde state, router metadata, or explicit paths.
- Discover sibling `home-` from `home` only when repository identity confirms it. Read `home-/AGENTS.md` before
  preference-sensitive home commands.
- Avoid recursive home scans by default. Use bounded discovery from explicit paths, known modules, managed targets, XDG
  metadata, and relevant app or package metadata.
- Require explicit confirmation before destructive actions, repository writes, package changes, or remote-host changes.
