---
name: tilde
description: Use for Tilde deployment, provisioning, and home-management work. Trigger for Tilde prompt markers such as `/tilde ...` or `$tilde ...`, `~ ...`, messages whose first word is `tilde`, or requests to deploy, update, align, repair, diagnose managed state, or work with Tilde home behavior.
---

# Tilde

Tilde is a standalone agent skill and control plane. The canonical contract is
[Specification](references/specification.md). Read that file before changing behavior or executing nontrivial Tilde
work. The `.agents/specs/tilde.md` path is only a symlink to the same canonical file.

The provisioning model is:

- Desired state comes from the current committed public/private home repositories.
- The only persistent Tilde state file is `~/.local/state/tilde/state.yml`.
- `state.yml` stores repository bindings and the last fully converged commit anchors.
- Planning evaluates current manifests and targeted live facts on every run.
- Every run compares current desired manifests with targeted live checks and idempotent actions.
- Failed, conflicted, or deferred runs do not advance `applied` anchors.
- The host-local lock is process coordination, not cleanup state.

When existing docs, code, habits, or memory conflict with `references/specification.md`, the specification wins.

## Agent Quickstart

When the user invokes a Tilde prompt such as `/tilde <command> [target] [qualifiers...]`:

1. For nontrivial work, read `references/specification.md` through EOF before acting. Loading this skill or seeing an
   embedded copy of it is not a substitute for reading the canonical specification.
2. Treat `/tilde`, `$tilde`, and similar Tilde prompt markers as agent prompt contracts. They are not shell commands.
3. Resolve the controller-side runtime entrypoint before shell execution. Use the loaded skill directory's `bin/tilde`;
   if that path is not available, use `~/.agents/skills/tilde/bin/tilde`. Do not rely on bare `tilde` being on `PATH`.
4. Identify the target: current host, the current host name, `host`, `ssh:host`, or an all-caps host group such as
   `ALL`, `HOME`, or `WORK`.
5. Classify the command from the Command Reference below.
6. Map agent-orchestrated commands to the Workflow Matrix before running helpers.
7. For remote targets, run `"$TILDE" preflight remote HOST --format json` before reading target state, generating
   plans, or applying results.
8. Use the resolved runtime entrypoint for script delivery. Generate plans, run live checks, and apply results on the
   target host, not on the controller.
9. Keep proposal-first behavior for destructive, preference-sensitive, privilege-requiring, or remote mutations.
10. After a successful mutating remote apply, run a cheap final status read on the target before closeout.
11. After the run, summarize successful, changed, deferred, conflicted, and failed work.

If a direct runtime call says a command is agent-orchestrated, stop trying shell variants of that command. Load this
skill, classify the command, and run the appropriate agent workflow.

Do not execute `/tilde ...` or `$tilde ...` in a terminal. `/tilde` is a prompt marker, and `$tilde` may be a Codex skill
trigger or shell variable expansion depending on the environment. Shell execution uses the resolved runtime entrypoint,
written as `"$TILDE"` in examples:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" help
"$TILDE" ssh spinoza
```

If the skill was loaded from another directory, set `TILDE` to that directory's `bin/tilde` instead. If a controller-side
`tilde` command is not found, do not search the filesystem for it; switch to the resolved runtime entrypoint.

For remote targets, the first target-state read must happen on the target through Tilde SSH transport. Do not
inspect the controller's `~/.local/state/tilde/state.yml` to discover a remote host's repository bindings, applied
anchors, level, platform, or bootstrap state. That file belongs only to the controller host.

## Target Grammar

Host-aware prompt commands accept these target forms:

- no target: current host, also called localhost.
- `host`: remote host shorthand for `ssh:host`, except when it names the current host.
- `ssh:host`: explicit remote host target.
- `GROUP`: a bare all-caps host group defined by the active home policy, such as `ALL`, `HOME`, or `WORK`.

If a bare host token equals the current host name, such as `hostname -s`, treat it as the current host and run the local
workflow. Use explicit `ssh:host` only when the user really wants SSH transport to that host, including self-SSH.

The public prompt commands are `deploy`, `update`, `repair`, `align`, `status`, and `doctor`. `help` and `handoff` are
runtime helper routes. Tilde intentionally has no public `create`, `init`, `adopt`, `clean`, `organize`, or `upgrade`
prompt commands; keep one-off home-management work as ordinary proposal-first agent work until it is mature enough for
the core command surface.

Bare all-caps targets are not hostnames. Expand them from the active `~/AGENTS.md` home policy before running any remote
work. Group expansion applies only to unprefixed target tokens; `ssh:host` is always an explicit host target. If the
policy does not define the requested group, ask the user for the host list. For explicitly requested configured groups,
report the expanded host list and continue; the prompt itself is consent to run the requested workflow. Ask only when
the group is undefined, ambiguous, unexpectedly expands outside active policy, or a later step requires separate
explicit confirmation. Run each host as a separate target workflow and report per-host results.

When traversing a host group, perform a bounded noninteractive reachability check before each host workflow. Skip
unreachable hosts and continue with the remaining hosts. Report skipped hosts separately; an unreachable host inside a
group is not a failure for reachable hosts. If every expanded host is unreachable, stop with a clear `deferred` result.
Use Tilde SSH transport for the reachability check itself. Do not use raw `ssh`, even for this cheap probe.
Keep each host's freshness preflight adjacent to that host's status, plan, and apply workflow. Do not preflight the
whole group, wait while other hosts mutate, and later rely on those earlier results. Parallel group execution is valid
only when each independent host job contains its own preflight-to-verification sequence.
If reachability fails with `Host key verification failed` or another SSH host-key trust error, report it as a skipped
trust deferral. Do not run `ssh-keyscan`, disable strict host-key checking, edit `known_hosts`, or accept host keys
automatically. If suggesting remediation, name the exact host and trust effect; automated enrollment needs explicit
operator approval for the exact hosts.

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
host=spinoza
"$TILDE" ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" << 'SCRIPT'
printf 'ok\n'
SCRIPT
```

## Runtime

The PATH-visible runtime surface is `bin/tilde`, `bin/sudo`, and helper commands intentionally exposed in the Tilde
runtime PATH. Normal command implementations live in `libexec/` and are dispatched through `bin/tilde`.

Controller-side runtime calls must go through the resolved entrypoint. Bare `tilde` is valid only when the Tilde runtime
PATH is already active, such as inside a remote script delivered by Tilde SSH transport.

`bin/tilde` has direct runtime routes for helper and diagnostic commands. It intentionally refuses agent-orchestrated
prompt commands; those commands are interpreted and orchestrated by the loaded Tilde skill.

Implementation routes such as `plan` and `apply` are stable primitives for agent workflows. They are not user-facing
prompt commands. Use them only inside the workflow patterns in this skill and the specification.

## Command Reference

Commands are grouped by execution model.

### Agent-Orchestrated Prompt Commands

The agent interprets these high-level commands and orchestrates the workflow. They have no direct runtime route.

- `deploy`: prepare a local or remote host and apply desired state.
- `update`: refresh package managers, reconcile current desired state, and run `Update` sections.
- `repair`: apply the current desired state again; it does not read a repair queue or module-level state.

Treat `dry-run`, `plan-only`, `--managed`, and `--greedy` as qualifiers. `update --greedy` uses refresh mode with
managed non-system package refreshes and broad package-manager upgrade actions; do not use or reintroduce a separate
`upgrade` prompt command.

### Direct Runtime Commands

These commands have direct `bin/tilde` runtime routes. For remote targets, deliver the command through
Tilde SSH transport so the target host supplies live facts.

- `help`: show public commands or one command's usage.
- `doctor`: diagnose state, repository, target, and managedness problems without executing module code or mutating
  targets.
- `handoff`: copy and print the privilege handoff command for the local or remote host.
- `status`: show compact repository bindings and last fully converged anchors.

### Dual Command

- `align`: local link, copy, seed, and reset reconciliation can run directly through the resolved runtime entrypoint.
  Remote align remains agent-orchestrated: use `/tilde align spinoza` prompt semantics and deliver the target-side
  workflow through Tilde SSH transport. Do not run `tilde align --format json` on a remote target; `align` has no
  `--format` option.

### Implementation Routes

- `ssh`: deliver scripts to a remote host with the Tilde runtime environment active.
- `plan`: produce a plan from current committed repository content and target-host facts.
- `apply`: apply one or more plan files.
- `sudo`: classify privilege needs and support handoff.
- `boot`, `checkout`, `preflight`, and `smoke`: specialized runtime helpers.

Do not present implementation routes as user-facing Tilde prompt commands. When using them on the controller, use the
resolved runtime entrypoint with undotted route names such as `"$TILDE" plan` and `"$TILDE" apply`.

## Workflow Matrix

Agent commands map to planning modes and module sections as follows.

| Prompt command | Plan mode | Module behavior |
| --- | --- | --- |
| `deploy` | `apply` | `Prerequisites`, declared package installs, `Install`, `Post Install` when the install phase changed, declared files and links, then `Configure` |
| `update` | `refresh`; `repair` for state recovery | package refresh, `Prerequisites`, declared package installs, `Install`, `Post Install` when the install phase changed, declared files and links, `Update`, then `Configure` |
| `update --managed` | `refresh --managed` | update behavior, plus managed non-system package refreshes |
| `update --greedy` | `refresh --greedy` | managed update behavior, then broad package-manager upgrade actions |
| `repair` | `repair` | `Prerequisites`, declared package installs, `Install`, `Post Install` when the install phase changed, declared files and links, then `Configure` |
| `align` | `align` | directories, links, copies, seeds, and resets only; no bootstrap, packages, or module code |

The prompt command is `update`; the ordinary plan mode is `refresh`. Do not call or invent `--mode update`. If target
status shows missing `state.yml` or no `applied` anchors, recover state with `plan --mode repair` for that run; do not
use refresh merely to recreate state, and do not tell the user to run deploy solely to initialize state. Missing
`state.yml` is not proof that the host was never deployed; describe it as missing state and state recovery unless
bounded evidence proves otherwise. State recovery uses repair because it avoids `Update` sections while recreating
fully converged bindings and anchors.

`update` / `refresh` reconciles current desired-state declarations, including newly declared packages, links, copies,
seeds, and resets. Present packages return `unchanged`, missing packages are installed, and a fully successful
Tilde-generated refresh plan may advance `applied` anchors. The default refresh updates system package managers such as
Homebrew and apt. `--managed` also refreshes managed non-system package declarations. `--greedy` implies `--managed`
and appends broad package-manager upgrade actions. Use `repair` when the intent is desired-state convergence without
package refreshes, broad package upgrades, or `Update` sections.

When an agent workflow materializes plan JSON files, create them under a per-run temporary directory and remove that
directory at exit. Do not write fixed plan paths such as `/tmp/opencode/HOST-public.json`, and do not leave plan files
behind after `tilde apply`. If generated plan files will be applied, generate and apply them inside the same temporary
directory lifetime. A separate plan-only preflight is disposable and must not be described as the plan that was later
applied:

```bash
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

"$TILDE" plan --mode refresh --repo ~/Dropbox/home --host newton --format json > "$tmpdir/public.json"
"$TILDE" apply --plan "$tmpdir/public.json"
```

Successful Tilde-generated `refresh` plans advance `applied` anchors after every required action succeeds. If a refresh
apply returns `deferred`, `conflict`, or `notok`, anchors stay unchanged and the run did not fully converge.

### Command Result Integrity

Run critical Tilde commands directly and let the tool runner observe their real exit status. This applies to `status`,
`doctor`, `preflight`, `checkout`, `plan`, `apply`, `align`, and final verification.

Never use diagnostic wrappers such as:

```sh
tilde plan ... 2>&1 || echo "PLAN_EXIT: $?"
tilde apply ...; echo "APPLY_EXIT: $?"
```

They turn failure into apparent success and can mix diagnostics into JSON. Redirect only stdout when capturing
machine-readable output, leave stderr separate, and preserve a non-zero status explicitly only when the workflow must
parse a structured failure document.

### Local Update Binding

For a local update, derive repository paths, mode, host, platform, and level from local status just as remote workflows
derive them from target status. Do not retype values observed in status output:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

"$TILDE" status --format shell > "$tmpdir/status.sh"
. "$tmpdir/status.sh"
[ -n "$tilde_public_repo" ] || exit 1

"$TILDE" plan \
  --mode "$tilde_update_mode" \
  --repo "$tilde_public_repo" \
  --host "$tilde_host" \
  --platform "$tilde_platform" \
  --level "$tilde_level" \
  --format json > "$tmpdir/public.json"
```

Generate the optional private plan in the same directory, then use the captured-apply JSON parsing pattern from the
remote workflow below. Do not redirect plan stderr into its JSON file.

## Remote Script Execution

### Remote Freshness Preflight

Remote Freshness Preflight is the first remote workflow step. Before any remote `status`, `plan`, `apply`, or
state-recovery decision, run the deterministic controller-side preflight route:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" preflight remote spinoza --format json
```

The route does not require a working target Tilde runtime. It uses Tilde SSH transport without target runtime injection
and returns one JSON document that classifies reachability, bootstrap baseline, repository backend, target runtime,
Dropbox runtime, target state, repository bindings, sudo state, controller runtime commit, and `next` steps.
It does not report the apply lock or prove that no apply process is active. A successful preflight, current runtime, or
clean repository is never evidence that a previously observed lock has cleared.

Use `bootstrap.needed` and `next` from this JSON for the initial bootstrap decision. Do not infer bootstrap need from
free-form logs, guessed package state, or controller-side state. The bootstrap baseline is intentionally small:
Homebrew, `curl`, `git`, and `ruby` must be usable on the target.

`sudo.noninteractive` is the broad `sudo -n true` probe. It may be false on Linux hosts that intentionally allow only
package-management commands without a password. For ordinary `update`/`repair` package work, use `sudo.apt` to
recognize that `apt-get` commands can run noninteractively. Do not run handoff merely because
`sudo.noninteractive=false`; run handoff only when preflight `next` asks for it, or when the actual apply returns a sudo
deferral.

For Dropbox-backed interactive hosts, the durable runtime shape is:

```text
~/.agents/skills/tilde -> ~/Dropbox/tilde
```

A clean clone at `~/.agents/skills/tilde` is only a provisional bootstrap or freshness runtime. Convert it with
`"$TILDE" checkout runtime-link --host HOST --source '~/Dropbox/tilde' --target '~/.agents/skills/tilde' --expected COMMIT`
only when the preflight JSON shows the Dropbox runtime exists, is a Git checkout, has executable `bin/tilde`, is clean,
and matches the controller runtime commit. If the Dropbox checkout is absent, dirty, missing `bin/tilde`, or stale,
defer the symlink conversion instead of replacing it with a controller bundle.

The controller-side loaded skill is the source for the expected Tilde runtime commit.

For mutating remote prompt workflows such as `deploy`, `update`, `repair`, and remote `align`:

- Compare the controller runtime commit with the target `~/.agents/skills/tilde` commit before the first target-state
  read.
- If the target runtime is a stale Git checkout, refresh it from the controller checkout with `"$TILDE" checkout remote`
  before running target `tilde status`, `tilde plan`, or `tilde apply`.
- If the target runtime is stale but cannot be refreshed safely because it is dirty, missing, not a Git checkout, or
  otherwise ambiguous, stop with `deferred`. Do not continue into state recovery with the stale runtime.
- If a clean target runtime cannot fast-forward because its history differs from the controller runtime, refresh it with
  `--replace-clean`. Do not use `--replace-clean` for public/private desired-state checkouts unless the operator has
  explicitly approved replacing that clean checkout.
- Do not patch, edit, or `sed` the target runtime checkout as part of the deploy/update/repair workflow or continue as
  if a target-side patch completed the workflow. If live debugging requires a temporary target edit, treat it as a
  separate explicitly approved recovery/debug operation, capture the diff, port accepted changes to the controller
  source repository, then refresh the target through checkout freshness routes before retrying.
- On Git-backed remote hosts, also refresh the target public/private desired-state checkouts from the controller
  repositories before planning. If a target checkout is dirty or cannot be fast-forwarded from the controller bundle,
  stop with `deferred`.
- On Dropbox-backed remote hosts, do not replace synced repositories with controller bundles; report stale or unsynced
  target checkouts as `deferred` unless the user asks for a Git-backed checkout refresh.
- If preflight reports `cleanup-sudoers`, run `"$TILDE" sudo cleanup --host HOST` after the privilege-dependent workflow
  no longer needs the temporary handoff rule, then verify the next preflight no longer reports it.

When using `checkout remote`, always pass the complete source and target binding. For target runtime freshness, the
controller repository is the loaded skill root and the target is `~/.agents/skills/tilde`:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
controller_runtime=${TILDE%/bin/tilde}
"$TILDE" checkout remote --host spinoza --repo "$controller_runtime" --target '~/.agents/skills/tilde'
```

For Git-backed desired-state checkout freshness, pass the selected controller data repository and the target checkout:

```bash
"$TILDE" checkout remote --host vps --repo ~/Dropbox/home --target '~/.local/src/home'
```

Do not call `checkout remote` with only `--host`; the route cannot infer which controller repository maps to which
target checkout. Quote target paths that start with `~` so the controller shell does not expand them to the controller
home before the remote receives the path.

If `checkout remote` fails before delivery because the controller repository is dirty, lacks an upstream, or is ahead
of upstream, treat that as a controller-source blocker, not a target failure. Do not commit, push, pass
`--allow-unpushed`, or change checkout options automatically. Report the blocking repository and status, leave already
successful hosts alone, and mark only the affected host as `deferred` or partial. If the operator explicitly approves
the needed commit/push or unpushed-bundle retry, perform that separate source-control step and resume the affected host
from the freshness checkout step.

For read-only remote workflows such as `status` and `doctor`, detecting a stale target runtime is a reportable stale
runtime condition, not permission to mutate the remote host. Report it and stop unless the user requested repair or
update behavior.

A status output that mentions state paths outside this specification, such as `~/.local/state/tilde/config.yml` or
`~/.local/state/tilde/hosts/HOST/state.md` means the target runtime is stale. Stop and refresh or report the stale
runtime before any `plan --mode repair` step. Do not describe state writes outside the `state.yml` model as successful
state recovery.

Use the resolved runtime entrypoint for all remote script execution:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza
```

It sets up the correct Tilde runtime environment (non-secret `~/.config/environment.d/*.conf` values, PATH, TILDE_ROOT,
TILDE_SUDO) and delivers the script body through `ssh host sh -s --`.

Do not use raw `ssh`, `sh -c`, or `bash -lc` for multi-command remote work.
These bypass Tilde's PATH setup and sudo interceptor.

After the Remote Freshness Preflight, plan and execute on the target host. Platform detection, package inventory,
repository bindings, and live checks come from the target. A controller-side plan for a remote host is invalid.
After the target runtime is known current, read target status in shell format when a remote script needs repository
bindings:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
status_sh=$tmpdir/status.sh

tilde status --format shell > "$status_sh"
. "$status_sh"
SCRIPT
```

Use the returned `tilde_public_repo` and `tilde_private_repo` paths when generating target-local plans, and use
`tilde_update_mode` for update state recovery. Do not hard-code `~/Dropbox/home`, `~/Dropbox/home-`,
`~/.local/src/home`, or `~/.local/src/home-` unless those paths came from target status, explicit user arguments, or
active home policy for a stale Git-backed target that must be refreshed before status can be trusted.

For a fresh remote `deploy`, `state.yml` may not exist yet, so `tilde status --format shell` may not return repository
bindings. If the immediately preceding preflight proves a Dropbox-backed target has clean public/private repositories,
use those target-side preflight paths as the first deploy bindings. If preflight does not prove the path, stop with
`deferred`; do not invent a target repository path from controller conventions.

For Git-backed targets whose status binds repositories outside Dropbox, controller-side `~/Dropbox/...` source paths are
not target paths. Do not create target-side `~/Dropbox` for repository binding, cleanup, shared app state, or convenience
paths unless active target policy explicitly says that host has Dropbox-backed storage.

When a remote workflow needs repository bindings in a target-side script, bind them from target status shell output
before planning. Do not retype host-convention paths in `tilde plan --repo ...` commands:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
status_sh=$tmpdir/status.sh

tilde status --format shell > "$status_sh"
. "$status_sh"
if [ -z "$tilde_public_repo" ]; then
  printf '%s\n' 'STATUS_FAILED: missing tilde_public_repo' >&2
  exit 1
fi
SCRIPT
```

Remote state is target-local. For `/tilde update spinoza`, `/tilde update ssh:spinoza`, `/tilde deploy spinoza`,
`/tilde deploy ssh:spinoza`, `/tilde doctor spinoza`, `/tilde status spinoza`, and `/tilde align spinoza`, do not read the controller's
`~/.local/state/tilde/state.yml`. If state or repository bindings are needed, read them on the target:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
status_sh=$tmpdir/status.sh

tilde status --format shell > "$status_sh"
. "$status_sh"
if [ -z "$tilde_public_repo" ]; then
  printf '%s\n' 'STATUS_FAILED: missing tilde_public_repo' >&2
  exit 1
fi

tilde plan \
  --mode "$tilde_update_mode" \
  --repo "$tilde_public_repo" \
  --host "$tilde_host" \
  --platform "$tilde_platform" \
  --level "$tilde_level" \
  --format json > "$tmpdir/public.json" || exit $?
if [ -n "$tilde_private_repo" ]; then
  tilde plan \
    --mode "$tilde_update_mode" \
    --repo "$tilde_private_repo" \
    --host "$tilde_host" \
    --platform "$tilde_platform" \
    --level "$tilde_level" \
    --format json > "$tmpdir/private.json" || exit $?
  set -- --plan "$tmpdir/public.json" --plan "$tmpdir/private.json"
else
  set -- --plan "$tmpdir/public.json"
fi

apply_json=$tmpdir/apply.json
apply_status=0
tilde apply "$@" > "$apply_json" || apply_status=$?

ruby -rjson -e '
def snippet(value)
  text = value.to_s
  return nil if text.empty?

  text.lines.map(&:rstrip).reject(&:empty?).join("\n")[0, 800]
end

def bad_summary(result)
  diagnostics = result["diagnostics"] || {}
  runs =
    if diagnostics["blocks"].is_a?(Array)
      diagnostics["blocks"]
    elsif diagnostics["commands"].is_a?(Array)
      diagnostics["commands"]
    else
      []
    end
  failed = runs.reverse.find { |run| run["exit"].nil? || run["exit"].to_i != 0 } || runs.last
  summary = {
    action_id: result.fetch("action_id"),
    status: result.fetch("status"),
    reason: diagnostics["reason"]
  }
  if failed
    summary[:command] = failed["command"]
    summary[:exit] = failed["exit"]
    summary[:stderr] = snippet(failed["stderr"])
    summary[:stdout] = snippet(failed["stdout"])
  end
  summary.compact
end

data = JSON.parse(File.read(ARGV.fetch(0)))
bad = data.fetch("results").select { |r| ["deferred", "conflict", "notok"].include?(r.fetch("status")) }
counts = data.fetch("results").each_with_object(Hash.new(0)) { |r, h| h[r.fetch("status")] += 1 }
puts JSON.generate(
  completed: data.fetch("completed"),
  counts: counts,
  bad: bad.map { |r| bad_summary(r) }
)
exit(data.fetch("completed") && bad.empty? ? 0 : 1)
' "$apply_json" || exit $?
[ "$apply_status" -eq 0 ] || exit "$apply_status"
SCRIPT
```

Replace repository paths with the target host's configured bindings. Omit the private plan when the target has no
private repository.

For remote align, use the same target-local workflow and apply-capture pattern with `mode=align`. Do not call the
target's direct `tilde align` route for a remote prompt workflow, and do not suppress diagnostics.

Every Tilde `status`, `doctor`, `checkout`, `plan`, `apply`, `align`, or verification step must treat a non-zero exit
as failed, deferred, or conflicted, even when stdout is empty. Do not redirect stderr to `/dev/null` for these steps,
locally or remotely. Do not append `; echo "EXIT: $?"`, `|| true`, or similar status markers to critical Tilde
commands; they mask failures and can corrupt machine-readable output. If a tool UI needs an exit marker, first write the
command stdout to a temporary file, preserve the command status in a variable, parse the file, then print any marker
separately. A later successful status read does not turn a failed plan, apply, checkout, or align step into success.

Do not run `tilde apply` with `2>&1` when stdout will be parsed as JSON. Keep apply stdout as one JSON document and keep
stderr separate.

After `tilde apply`, inspect the JSON action results with a JSON parser such as Ruby's `JSON` library or `jq`. Do not
use `grep`, `rg`, or line counts to classify statuses. The apply stdout must remain one parseable JSON document; treat
malformed or mixed output as failed. `completed: true` only means the action list was processed; it is not full success
when any result is `deferred`, `conflict`, or `notok`. Treat such a run as incomplete and report the exact action
status, `action_id`, and reason.

When an apply result contains `deferred`, `conflict`, or `notok`, do not immediately run a second apply or repeat the
same `update` just to see whether it clears. Inspect the captured JSON and stderr from that attempt. Retry only after a
specific source fix, approved operator recovery, or observed external-state change explains why the next attempt is
different; otherwise report the host as incomplete.

For nontrivial plans, do not stream full `tilde apply` JSON directly to a truncating tool UI. Capture stdout to a
per-run temp file, leave stderr visible or capture it separately, parse the captured JSON immediately, and print a
compact summary. Do not run `tilde apply` a second time merely to reconstruct the status summary; if the original apply
JSON was not captured, report that validation gap instead of pretending a later successful status read or rerun describes
the first apply.

Each host gets one apply attempt at a time. If the controller tool times out or loses the connection, assume the
target-side apply may still be running. Before any retry, inspect the target lock and active Tilde/apply processes with
bounded read-only checks. If an apply process or held lock remains, do not retry; report that host as active/deferred and
leave it running. Never use an agent tool-output cache or a second apply as a substitute for the original captured
`apply.json`.

If `tilde apply` exits non-zero, parse its captured stdout only when that file contains a structured apply result. A
current runtime emits `completed: false` JSON for lock contention. Empty or malformed stdout is a runtime/protocol
failure; report the visible stderr and do not hide it behind a JSON parser error.

After a successful mutating remote apply, verify target convergence with a separate cheap status read so the apply JSON
stays easy to parse:

```bash
TILDE=${TILDE:-"$HOME/.agents/skills/tilde/bin/tilde"}
"$TILDE" ssh spinoza << 'SCRIPT'
tilde status --format markdown
SCRIPT
```

Use `target HEAD` or `target current commit` for the repository commit currently checked out on the remote host. Use
`applied anchor` for the commit recorded under `applied` in the target's `state.yml`. Do not call a remote repository
HEAD `local` in summaries; that word is ambiguous from the controller.

Inside the remote script body, bare `tilde` is valid because Tilde SSH transport places the target runtime directory at
the front of `PATH`.

Remote scripts must be `sh`-compatible by default. Use the plain `"$TILDE" ssh HOST << 'SCRIPT'` form for ordinary
status, plan, apply, and verification work. Do not pass `-- bash` for macOS targets or for scripts that can run under
`sh`. Passing an interpreter after `--` is reserved for a verified non-macOS target and a script that truly needs syntax
absent from `sh`.

In the default remote form, `sh`-compatible means POSIX `sh`, not "Bash without a Bash shebang." Do not use the Bash
skill prelude in these remote scripts. Avoid common Bashisms:

| Bashism | POSIX `sh` form |
| --- | --- |
| `set -o pipefail` | avoid critical pipelines; check each command separately |
| `[[ -n $x ]]` | `[ -n "$x" ]` |
| `[[ $x =~ re ]]` | `case $x in pattern) ... ;; esac` |
| `arr=(a b)` and `${arr[@]}` | newline-separated strings, positional parameters, or repeated commands |
| `source file` | `. file` |
| `function name { ...; }` | `name() { ...; }` |
| `local x=...`, `declare`, `mapfile`, `readarray`, `select` | simple variables and explicit loops |
| `< <(cmd)` and `<<< "$text"` | temp files, pipes, or here-documents |
| `{foo,bar}` brace expansion | spell out the words |
| `$'...\n...'` strings | `printf '%s\n' ...` |

Also remember that `dash` is a common `/bin/sh`; scripts that only work in Bash are not acceptable in the plain remote
form.

Use `"$TILDE" ssh --tty spinoza` for interactive remote sessions that require a pseudo-terminal (e.g., `sudo` password
prompts).

## Module Model

Module README code sections use this stateless contract:

- `Prerequisites`: external requirements and read-only checks only. Failed checks return `deferred`.
- `Install`: idempotently ensure packages, tools, directories, applications, repositories, or local resources are present.
- `Post Install`: runs only when declared package installs or `Install` changed something in the current run; correctness
  must not depend on it.
- `Configure`: idempotent desired configuration. It runs after declared directories, links, copies, seeds, and resets
  are materialized, and after `Update` in update mode.
- `Update`: explicit refresh or upgrade work.
- `Notes`: informational only; never executed.

Code blocks must be idempotent or guarded. If an effect cannot be detected from live target facts, represent it as a
prerequisite, note, or explicit proposal-first operator action.

Package managers are the source of truth for package presence. Package inventories are ephemeral, in-memory
optimizations only.

Module code blocks call Tilde helpers by their plain names, such as `line` and `span`. Privileged helper calls use the
same plain form with `sudo`, such as `sudo line ...`.

Platform-specific module code belongs under platform section groups such as `## Linux` or `## MacOS`, with ordinary
action sections nested below them, for example `### Install` or `### Configure`. A platform-scoped section makes the
module applicable for that platform; do not add placeholder platform frontmatter, links, directories, or packages just
to make the section run.

README frontmatter may declare `directories` along with `links`, `copies`, `seeds`, `resets`, and `packages`. Link
sources are repository-relative by default. A source that starts with `~/` or `/` is a target-home source and must stay
inside the target home. Use target-home sources for live home paths such as Dropbox-backed shared state directories and
XDG entrypoints; Dropbox-to-Dropbox symlink values must be relative to the target directory.

`phase: early` is reserved for small prerequisite-style modules whose actions must run before normal actions across all
plans in the same apply run, such as a private Linux sudoers baseline. Do not use it for ordinary ordering preferences.

## Safety

Proposal-first behavior is required before replacing unmanaged files, removing stale links or managed spans, backing up
conflicting paths, uninstalling packages, running non-idempotent code, requiring privileges, mutating remote hosts, or
performing one-off operator workflows.

Managedness must be proven before destructive cleanup. No proof means no destructive mutation.

When apply reports `conflict`, stop after reporting the exact conflicted targets and wait for an explicit user response
before replacing files, forcing links, copying repository versions over targets, or rerunning apply. Do not infer consent
from silence, from the fact that a conflict exists, or from the agent's own question. Conflict resolution may reveal
additional conflicts in a later apply; repeat the same explicit-approval step for each newly revealed conflict.

Exception: during a fresh `/tilde deploy` with no existing applied anchors, treat declared-target conflicts as install
replacement. Back up the exact existing target when practical, remove only that exact target, rerun apply, and report
the replacement. Do not ask again for ordinary fresh-install overwrites such as `~/.bashrc`. This exception does not
apply to `update`, `repair`, `align`, broad directory cleanup, package removal, or paths outside declared targets.
For example, if `public/bash:link:bashrc->~/.bashrc` conflicts with a default real `~/.bashrc`, back up `~/.bashrc`,
remove only `~/.bashrc`, and rerun apply so the managed symlink is created.

If the user chooses repository replacement for a conflict, back up the exact target when practical, remove only the exact
conflicting target, and rerun apply so the normal declarative action recreates it. Do not rerun apply expecting a
default conflict result to overwrite the target. Broad cleanup, such as clearing an entire font directory after
package-manager file conflicts, requires a separate explicit approval that names the directory and effect.

If an apply command times out or reports `state lock busy`, do not delete the lock file as a first response. A lock held
with `flock` belongs to a process, and removing the pathname does not prove the process stopped. Treat this as
`deferred` or an active-run check: use bounded read-only process inspection on the target, wait when a Tilde/apply
process is still active, and remove a leftover lock only after proving no process holds it and getting explicit approval.
Missing `lsof` is not proof that no process holds the lock; prefer a nonblocking `flock` probe when cleanup is approved
or required.

If sudo is required and noninteractive sudo fails, report `deferred` and present:

```bash
"$TILDE" handoff --host spinoza --copy
```

Run the helper on the controller, not inside `"$TILDE" ssh`. The helper prefers the short runtime handoff command when
the local or target runtime supports it; otherwise it prints the self-contained bootstrap fallback. It reports whether
it copied the command to the controller clipboard. The command must work when pasted into bash, zsh, or fish. Copy or
present the `Handoff command:` line exactly; do not rewrite it, split it into a `TILDE=...` assignment plus an `ssh`
command, replace the remote path with a local variable, or add extra quoting. The printed command is also valid during
first-time bootstrap before the target runtime exists; do not replace it with an ad hoc sudoers one-liner. Wait for the
user to run it, then rerun the affected action and verify cleanup. Do not collect passwords in chat.

## Weak-Model Guardrails

For weaker or low-context agents:

- Plan from current committed repositories and targeted live facts.
- If reading `references/specification.md` is truncated, reopen later line ranges until the relevant instruction file is
  read through EOF before changing behavior.
- Treat `Prerequisites` as read-only checks.
- Advance `applied` anchors only after every required action succeeds.
- Keep `applied` anchors unchanged after `deferred`, `conflict`, or `notok`.
- On timeout or `state lock busy`, do not remove `~/.local/state/tilde/lock` blindly. Check whether an apply process is
  still active and treat uncertainty as `deferred`.
- After an apply timeout or lost connection, do not retry that host until bounded target checks prove no apply process
  and no held lock remain. An active process or held lock means the host is still active/deferred.
- Preflight does not inspect the apply lock. Never infer that a lock cleared from `reachable`, `runtime.current`, clean
  repositories, or a preflight `next` list; probe the target lock and active apply processes explicitly.
- Do not remove remote Tilde lock files as routine closeout cleanup after a failed or partial apply. Lock cleanup is a
  separate recovery step after bounded holder checks and, when any uncertainty remains, explicit user approval.
- Never plan a remote host from the controller.
- For mutating remote workflows, verify target Tilde runtime freshness and Git-backed desired-state checkout freshness
  before the first target `status`, `plan`, or `apply`.
- Do not run target `tilde status`, `tilde plan`, or `tilde apply` through a stale target runtime. Refresh the target
  runtime first, or stop with `deferred` if it cannot be safely refreshed.
- Do not patch target runtime or desired-state checkouts as part of deploy/update/repair to work around a bug and then
  continue as if the workflow succeeded. Save the diff, report it, and fix the controller source repository through
  normal review and commit flow. Temporary target edits are allowed only as a separate explicitly approved
  recovery/debug operation.
- Never read controller `~/.local/state/tilde/state.yml` for a remote target.
- Never execute `/tilde ...` or `$tilde ...` in a shell; they are prompt markers, not runtime commands.
- Before any controller-side runtime call, resolve `TILDE` to the loaded skill directory's `bin/tilde`, falling back to
  `~/.agents/skills/tilde/bin/tilde`.
- If bare `tilde` is not found on the controller, do not search for it; rerun through `"$TILDE"`.
- Do not run agent-orchestrated prompt routes through `"$TILDE"`: `deploy`, `update`, and `repair`. `align` is a
  direct route only for current-host reconciliation; remote align is still a prompt workflow.
- For remote `/tilde align HOST`, do not run `tilde align --format json` on the target. Read target bindings on the
  target, then run `tilde plan --mode align --format json` for each target repository and `tilde apply` the plan files.
- Never redirect remote Tilde stderr to `/dev/null`. Non-zero remote exit status means the step failed, deferred, or
  conflicted, even when the tool output pane says `(no output)`.
- Keep `tilde apply` stdout parseable as one JSON document; do not merge stderr into it and do not append exit sentinels.
- For any large or host-group `tilde apply`, capture stdout to `$tmpdir/apply.json`, parse that file immediately, and
  print only a compact status summary. Do not stream huge apply JSON to the tool UI and then recover by rerunning apply.
- Do not validate Tilde apply by scraping agent-runner tool-output files, hard-coded output IDs, or truncated panes. The
  authoritative validation artifact is the apply JSON captured during the same workflow.
- After `tilde apply`, inspect action results with a JSON parser. Do not use `grep`, `rg`, or line counts for status
  classification, and do not report success only because JSON was printed or `completed` is true. Any `deferred`,
  `conflict`, or `notok` action means the run is incomplete.
- Do not treat an unexplained retry as diagnosis. After `notok`, do not rerun the same apply/update merely because it
  might be transient; retry only after a concrete source fix, approved recovery, or observed external-state change.
- After a `notok` section or package result, do not run module snippets manually on the target for debugging or repair.
  Diagnose from structured output and source, fix desired state, then retry through `deploy` or `repair`. Any
  target-side manual mutation is a separate operator workflow and needs explicit approval.
- Inspect `ignored` and empty-output `ok` actions against the requested host. A guarded desktop install that returns
  `ok` with no output may have skipped the real package work; verify expected package state and condition diagnostics
  for modules such as terminals, browsers, Flatpak apps, and desktop tooling.
- Package declarations without a `type:` prefix use the platform default package manager: `brew` on Linux and macOS,
  and `scoop` on Windows. Do not rewrite unprefixed Linux packages as `brew:` just for clarity, and do not inspect
  `dpkg` or apt state to decide whether an unprefixed package is installed. Debian packages must be declared with an
  explicit `deb:` prefix.
- For platform-specific module code, use `## Linux` / `## MacOS` / `## Windows` with nested action headings such as
  `### Install` or `### Configure`. Do not add dummy platform frontmatter, directories, links, packages, or platform
  `level` values just to force those nested sections to run.
- A final status read is verification only; it does not make an earlier failed remote `checkout`, `plan`, `apply`, or
  align step successful. Never mask those command exits with `; echo "EXIT: $?"`, `|| true`, or status-marker wrappers.
- Call `checkout remote` only with the complete mapping: `--host HOST --repo CONTROLLER_REPO --target TARGET_REPO`.
  Do not expect it to infer target paths from `--host`. Quote target paths that start with `~`.
- If `checkout remote` is blocked by a dirty, unpushed, or no-upstream controller repository, do not commit, push, or
  pass `--allow-unpushed` on your own. Report the blocker, keep host-group successes intact, and retry only the blocked
  host after explicit operator approval or source-control cleanup.
- Use the `plan --mode refresh` implementation route for the `update` prompt command only when target status has
  existing `applied` anchors. If target status shows missing `state.yml` or no `applied` anchors, use
  `plan --mode repair` for state recovery.
- Expect `/tilde update HOST` to install packages newly added to module frontmatter and to create newly declared links,
  copies, seeds, or resets. Use `/tilde update HOST --managed` to refresh managed non-system package declarations, and
  `/tilde update HOST --greedy` for broad package-manager upgrades. Use `/tilde repair HOST` only when the intent
  is convergence without package refreshes, broad package upgrades, or `Update` sections, or when missing state requires
  recovery.
- Treat `phase: early` as a cross-plan apply phase. Early actions from applicable modules run before normal actions
  across public/private plans; use it only for small idempotent prerequisites.
- For host-aware prompt commands, omitted target means current host. Treat bare `host` as `ssh:host`, except when it
  names the current host; then run the local workflow. Use explicit `ssh:host` to force SSH transport.
- Missing `state.yml` or missing `applied` anchors means state recovery, not proof that the host was never deployed.
- Remote status paths outside the `state.yml` model, such as `config.yml` or `hosts/HOST/state.md`, mean stale target
  runtime, not successful current state recovery.
- Treat bare all-caps targets such as `ALL`, `HOME`, and `WORK` as home-policy host groups, not hostnames. For defined
  groups, report the expanded host list and continue; do not ask for permission to start the exact requested workflow.
  Ask only if the active home policy does not define the requested group, the expansion is ambiguous, or it unexpectedly
  leaves active policy.
- When traversing a host group, skip unreachable hosts after a bounded reachability check and continue with reachable
  hosts. Run this check through `"$TILDE" ssh`; do not use raw `ssh` for Tilde remote workflow probes.
- Treat SSH host-key verification failures as reachability/trust deferrals. Do not run `ssh-keyscan`, disable host-key
  checking, edit `known_hosts`, or accept host keys automatically without explicit operator approval for exact hosts.
- After remote runtime freshness is verified, read `tilde status --format shell` on the target into a temp file, source
  it, and use the returned `tilde_public_repo`, `tilde_private_repo`, and `tilde_update_mode` variables for remote plan
  paths and update state recovery. Do not guess Dropbox or Git-backed checkout paths when status or explicit policy can
  supply them.
- For fresh remote `deploy`, if status has no bindings yet but preflight proved clean Dropbox-backed target
  repositories, use those preflight target paths for the first deploy apply.
- Do not create `~/Dropbox` on a target just because controller source repositories live under Dropbox, an example uses
  `~/Dropbox/home`, or post-update cleanup mentions Dropbox. If target status binds Git-backed repositories under
  `~/.local/src`, use those paths and skip Dropbox-only maintenance when `~/Dropbox` is absent.
- If active home policy asks for Dropbox conflicted-copy cleanup after update, apply that cleanup only to the bounded
  literal path named by the policy, normally `$HOME/Dropbox`. Do not substitute or additionally scan resolved Dropbox
  paths such as `$HOME/Library/CloudStorage/Dropbox` unless the active policy explicitly names them for cleanup.
- Use `mktemp -d` and `trap` for all local and remote plan JSON files. Generate and apply the plan files inside the same
  temporary directory lifetime when they are part of one workflow. Do not write fixed `/tmp/opencode/...` plan paths or
  leave generated plan files behind after apply.
- After a successful Tilde-generated `refresh`/`update` run, verify final status and report the updated `applied`
  anchors. If any action was `deferred`, `conflict`, or `notok`, anchors remain unchanged.
- Keep remote scripts `sh`-compatible unless Bash is explicitly required and the target is known to support it. Do not
  use Bash-only options such as `set -o pipefail` in the default `"$TILDE" ssh HOST << 'SCRIPT'` form.
- In default remote scripts, avoid Bashisms such as `[[ ]]`, arrays, `source`, `local`, `pipefail`, process
  substitution, here-strings, brace expansion, `mapfile`, and `$'...'` strings.
- Do not pass `-- bash` for macOS targets or ordinary remote status, plan, apply, and verification scripts.
- Treat package-manager metadata refresh warnings that report incomplete indexes, signature failures, or missing
  repository keys as `deferred`; do not summarize them as successful package refreshes.
- After a successful mutating remote apply, run a final target status read before the final answer.
- In remote summaries, distinguish `target HEAD` from `applied anchor`; do not call the target repository commit
  `local`.
- After an apply conflict, stop and wait for an explicit user answer before copying repo files over targets, forcing
  links, or rerunning apply. Newly revealed conflicts need a new explicit answer. Fresh `/tilde deploy` is the narrow
  exception: back up and replace exact declared targets automatically, then rerun apply.
- After the user chooses repository replacement for a conflict, back up and remove only the exact conflicted target, then
  rerun apply. Broad directory cleanup needs a separate explicit approval.
- Run `"$TILDE" handoff --host HOST --copy` on the controller after sudo deferral. Do not run handoff through
  `"$TILDE" ssh`, do not invent a two-line `TILDE=...` command, do not rewrite the printed `Handoff command:`, and do
  not replace first-time bootstrap handoff with a handcrafted sudoers command.
- Do not treat `sudo.noninteractive=false` as a handoff trigger by itself. On Linux update flows,
  `sudo.apt=true` means apt package work should be attempted normally; ask for handoff only after a real sudo deferral.
- Remove packages, file materializations, files, or spans only with explicit managedness proof and proposal-first
  confirmation.
- Prefer a safe `deferred` or `conflict` result over guessing.
