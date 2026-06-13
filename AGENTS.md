# Agent Development Guide

Scope: this file applies to agent work in this repository.

This repository contains the Tilde skill and control-plane helpers. It is intended to be installed as
`~/.agents/skills/tilde` and to operate on separate public/private home data repositories.

## Tilde Development

- Read `SKILL.md` before Tilde work; it links to the canonical specification and supporting references.
- Read `references/development.md` before editing provisioning behavior, helper scripts, skill metadata, or validation
  docs.
- Keep durable behavior in `references/specification.md`, reusable workflow in `SKILL.md`, and working drafts under
  `.agents/notes/`.
- Prefer `bin/tilde COMMAND ...` for runtime helper access. Command implementations live under `libexec/`. Direct
  helper paths such as `bin/plan`, `bin/apply`, `bin/status`, `bin/doctor`, `bin/bootstrap`, `bin/preflight`, and
  `bin/checkout` remain valid focused wrappers.
- Keep this root `AGENTS.md` limited to Tilde repository development. Target-home layout, cleanup policy, organization
  policy, and data-layer operation refinements belong in data repository `home/AGENTS.md` files, host README files, or
  module README files according to the spec.
