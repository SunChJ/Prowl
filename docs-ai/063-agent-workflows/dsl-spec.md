# Agent Workflow DSL — `prowl.workflow/v1` (living spec)

> Living document: the normative definition of the workflow file format, run semantics,
> and the CLI participant protocol. Updated in place as the design settles and the
> implementation lands; history and rationale live in [000-plan.md](000-plan.md).
>
> Status: **draft** (2026-08-21) — not yet implemented. Sections marked *TBD* are open.

## 1. Principles

1. **The DSL describes intent; the runner owns transport.** A file says "ask the reviewer
   for findings", never "inject via ghostty" or "use adapter X". Transports can change
   without touching workflow files.
2. **Declarative and sequential.** No shell, no scripts, no expressions. V1 control flow is
   ordered steps plus one bounded `repeat … until <verdict>`.
3. **Long content goes through files; only one line ever enters a TUI.**
4. **Portable by construction.** A file never names a local Agent Profile, pane, or run id.
   Bindings are resolved locally at start and remembered.
5. **Only run-bound panes are touched.** A workflow can speak only to its own roles.

## 2. Document structure

```yaml
schema: prowl.workflow/v1            # required
id: prowl.adversarial-review         # required slug; `prowl.` prefix reserved for bundled workflows
name: Adversarial Review             # required; UI title
description: …                       # optional; popover/Settings subtitle
icon: magnifyingglass.circle         # optional SF Symbol

inputs:                              # optional; provided by the start sheet or `--input k=v`
  max_rounds: { type: integer, default: 5, min: 1, max: 10 }
  focus:      { type: string,  default: "", prompt: "What should the reviewer focus on?" }   # string inputs are single-line (no line terminators / control characters), validated at start
  mode:       { type: enum, values: [strict, lenient], default: strict }

roles:   …                           # §3
steps:   …                           # §4
```

Sources and precedence: bundle (`Resources/workflows/`, ids `prowl.*`) < user
(`~/.prowl/workflows/*.yaml`) < repo (`<root>/.prowl/workflows/*.yaml`). A user/repo file may
not reuse a `prowl.*` id; the same non-reserved id in user and repo scope resolves to the
repo file for that worktree.

## 3. Roles

```yaml
roles:
  author:
    source: current                  # the pane the run was started from (needs a detected agent only if a step messages it — see table)
  reviewer:
    source: launch                   # Prowl starts a new agent for this role
    kind: interactive                # V1: interactive only; `headless` is a reserved V2 value (§12)
    agents: [codex, claude]          # optional allow-list of agent tokens (as in `prowl agents` `type`); omitted = any launchable
    suggest:                         # optional; match an existing enabled profile exactly, or offer to create one
      agent: codex
      reasoning_effort: xhigh
      execution_mode: standard
    bind: ask                        # ask (default) | auto
    placement: split                 # split | tab (default: split)
    direction: right                 # right | left | up | down (split only)
    background: false                # true = do not focus/select the new surface
  partner:
    source: pick                     # an existing detected agent pane in the SAME worktree, chosen at start (CLI: --role partner=p12)
```

| Field | Rules |
| --- | --- |
| `source` | At most one `current` role per workflow. A `current` role must host a detected agent only if some step that is not pre-skipped at start `message`s it; otherwise a bare shell pane is a valid source (context-only handoff, legacy `handoff save`). A workflow without a `current` role needs an explicit worktree at start. `pick` roles are chosen from the detected agents of the source worktree at start; a pane already in a run is not offered. |
| `kind` | Only for `launch`. V1 accepts `interactive` only; `headless` is reserved (§12) because no executor/output protocol exists yet. |
| `agents` | Tokens from the detected-agent catalog. Validator warns (not errors) when none is installed locally. |
| `suggest` | Subset of profile preset fields (`agent`, `model`, `reasoning_effort`, `execution_mode`). Never a reference to a profile name or UUID. |
| `bind` | `ask`: the start sheet always shows the role picker (pre-filled). `auto`: the sheet appears only when resolution is ambiguous. |

**Binding resolution** (per `launch` role, at start, in order): remembered local binding
→ enabled profile matching `suggest` exactly → Recommended profile (053 rules) filtered by
`agents` → ask. The memory key is the four-tuple
`(definition scope, workflow id, role, role-requirements digest)` where scope is
`bundle` | `user` | `repo:<repository id>` and the digest is SHA-256 over the canonical
JSON encoding (sorted keys, `agents` sorted, absent keys omitted) of the role's requirement
block `{source, kind, agents, suggest}` — so a change to any requirement invalidates the
memory while prompt-only edits keep it. This paragraph is the single normative definition;
§10 refers back to it. Every candidate, including a remembered binding or a `--role`
override, is re-validated first (exists, enabled, satisfies `agents`, adapter supports a
seeded prompt); a failing candidate falls through to the next tier. The chosen profile is
frozen into the run together with its launch plan; later profile edits do not affect the
run. CLI overrides are source-specific (§9): `--role <launch-role>=<profile name|uuid|auto>`,
`--role <pick-role>=<agent pane: pN | pane UUID>`; `current` roles take no override.

## 4. Steps

Each step has `id` (unique within the workflow), optional `title` (templated; shown in the
status center and panel), exactly one verb, and — on `message` and `launch` steps only —
an optional `expect` (§5) whose delivery role is the step's target role. `action`,
`notify`, and `close` cannot carry `expect` (validation error): they have no pane that
could deliver; native actions return synchronous typed outputs instead.

```yaml
steps:
  - id: brief
    title: "Author writing the brief"
    message: author                          # ① speak to a live interactive role
    instruction: |                           #    multi-line → materialized to run.dir/instructions/brief.md; one pointer line is typed
      Write a short brief for an adversarial reviewer: ## Scope, ## Claims, ## How to verify.
      Deliver it with the generated completion command.   # never spell `prowl workflow done` yourself — the runner appends the tokenized command
    expect: { output: brief, sections: ["## Scope", "## Claims"], timeout: 10m }

  - id: launch
    title: "Reviewer starting round 1"
    launch: reviewer                         # ② start a launch role with a kickoff prompt
    prompt: "Read {{ outputs.brief.path }} and the bundled reviewer skill, then review."
    skill: prowl.adversarial-reviewer        #    optional; bundled skill materialized to run.dir/skills/<id>/SKILL.md and referenced
    expect: { output: findings, sections: ["## Findings", "## Verdict"], verdict: [clean, issues], timeout: 30m }

  - id: rounds
    repeat:                                  # ③ bounded loop (V1: not nested; no `launch` inside)
      max: "{{ inputs.max_rounds }}"
      until: outputs.findings.verdict == clean
    steps:
      - id: fix
        title: "Round {{ loop.index }}: author addressing findings"
        message: author
        text: "Findings: {{ outputs.findings.path }}. Fix or rebut each item, commit, then deliver your disposition with the generated completion command."
        expect: { output: disposition, timeout: 30m }
      - id: rereview
        title: "Round {{ loop.index }}: reviewer re-checking"
        message: reviewer
        text: "Disposition: {{ outputs.disposition.path }}. Re-review the new commits and deliver findings with the generated completion command, choosing the verdict clean or issues."
        expect: { output: findings, verdict: [clean, issues], timeout: 30m }

  - id: context
    action: git.context                      # ④ built-in native action (Swift); outputs under {{ actions.<id>.* }}
    with: { root: "{{ worktree.path }}" }

  - id: done
    notify: "Adversarial review: {{ outputs.findings.verdict }} after {{ loop.count }} round(s)"   # ⑤

  - id: cleanup
    close: reviewer                          # ⑥ only launch roles; protected close (confirms if the agent is still running)
```

| Verb | Payload keys | Allowed target | Notes |
| --- | --- | --- | --- |
| `message: <role>` | `text` (single line, typed verbatim) **or** `instruction` (multi-line, materialized + pointer) | live interactive role (`current`, `pick`, or a `launch` role already launched) | Injection is gated: `blocked` → not typed, run → `needsAttention`; `working` → the line is accepted by the agent runtime's own input queue (Prowl keeps none), shown in the panel. |
| `launch: <role>` | `prompt` (kickoff, templated), optional `skill` (an id from the embedded skill registry — same pattern as a workflow id, e.g. `prowl.adversarial-reviewer`; it must resolve to a bundled skill, unknown ids are validation errors; custom skills are V2) | `launch` role, at most once per run (V1) | Profile plan with `AgentStartIntent.prompt`. The single-/multi-line decision is made on the *rendered* prompt: one line → passed verbatim (after the §10 rendered-text check); otherwise materialized, and the kickoff becomes the pointer line. |
| `action: <id>` | `with` (templated map) | — | V1 registry: `handoff.transition` (inputs `briefing?`, `from`, `to`; performs archive-first `.prowl/handoff/` transition; outputs `kickoff_prompt`, `artifact_path`, `has_briefing`), `handoff.checkpoint`, `git.context`. Every registered action declares a typed schema for its `with` inputs (required/optional) and its output keys; `prowl workflow schema` prints them. |
| `notify: <text>` | — | — | Bell pipeline; click focuses the `current` role's pane, or — when the workflow has no `current` role — the source worktree (status panel). |
| `close: <role>` | — | `launch` roles | Never implicit; cancel never closes panes. |
| `repeat` | `max` (required), `until` (optional), `steps` | — | While-loop semantics: `until` is evaluated **before entering** and **after every iteration**, so a verdict already satisfied by an earlier step skips the loop. `until` compares a declared verdict only: `outputs.<name>.verdict == <value>` or `in [..]`, every literal must belong to that output's declared `verdict` set. `max` is either a positive integer literal or a template that references exactly one `integer` input (nothing else); it is resolved at start, must lie in `1…20` (the V1 ceiling), and an invalid value is `WORKFLOW_INVALID` (literal) or a start-time `INVALID_ARGUMENT` (input). Reaching `max` with `until` still unsatisfied (or absent) ends the run as `max_rounds_reached`. |

**Typed line formats and the completion-command renderer.** Every line Prowl types into a
pane starts with `[Prowl] ` so its origin is visible. `text` → `[Prowl] <text>`;
`instruction` → `[Prowl] Read <absolute path> and follow it`. Every *rendered* line is
checked before insertion: it must contain no line terminator or control character
(§10, "Rendered-text boundary"). When the step has an `expect`, one **completion-command
renderer** — the only place that spells the command — appends the activation's command
(§5): without `verdict`, ` — finish with: PROWL_WORKFLOW_TOKEN=<token> prowl workflow done
-`; with `verdict: [clean, issues]`, one complete, directly executable command per allowed
value joined by ` or `: ` — finish with: PROWL_WORKFLOW_TOKEN=<token> prowl workflow done
--verdict clean -  or  PROWL_WORKFLOW_TOKEN=<token> prowl workflow done --verdict issues -`
(no placeholders, nothing to substitute; `verdict` is limited to 2–4 values so the line
stays bounded). The materialized instruction file and `prowl workflow status` list the
same commands. The same renderer produces the watchdog nudge
(`[Prowl] When your work for this step is fully complete, finish with: <rendered command>`)
and every re-delivery after Relaunch, so no path ever shows a token-less or
verdict-less command. Authors never spell the command (the validator warns when
`text`/`instruction` contains `prowl workflow done`).

**V1 native action schemas** (normative summary; `prowl workflow schema` prints the full
JSON Schema):

| Action | `with` inputs | Outputs |
| --- | --- | --- |
| `handoff.transition` | `briefing` (path, optional), `from` (role, required), `to` (role, required), `note` (string, optional) | `kickoff_prompt` (string), `artifact_path` (path), `has_briefing` (bool) |
| `handoff.checkpoint` | `briefing` (path, required), `note` (string, optional) | `artifact_path` (path) |
| `git.context` | `root` (path, optional; default worktree) | `path` (path to the generated markdown summary), `branch` (string) |

## 5. `expect`

```yaml
expect:
  output: findings          # output name; default = step id; the same name may be produced by several steps (latest wins)
  format: markdown          # markdown (default) | text | json (parseable)
  sections: ["## Findings"] # markdown: required headings (fence/preamble stripped before checking, as HandoffStore.validatedBriefing)
  verdict: [clean, issues]  # declares 2–4 allowed values (safe slugs); the rendered completion command then carries `--verdict <value>` and it becomes mandatory
  timeout: 2h               # optional hard cap; NO default — without it Prowl waits as long as the agent works
  on_timeout: attention     # only with `timeout`: attention (default) | skip | cancel
```

- **Invocation and activation identity.** Every execution of a `message` or `launch` step
  — once for a plain step, once per iteration inside `repeat`, again after Relaunch —
  mints a run-global, monotonic **invocation ordinal** (1, 2, 3, … across all steps and
  iterations) on entry, whether or not the step waits; it names the step's artifacts
  (`instructions/<step>.<ordinal>.md`). When the step has an `expect`, the same invocation
  is also its *activation* `(run id, step id, ordinal, delivery role)`: the runner mints a
  fresh delivery token for it, and the previous activation of the same step (if any) is
  terminal. Exactly one successful `done` is accepted per activation, identified by its
  token; a later, stale, or token-less delivery gets `STEP_NOT_EXPECTING` /
  `TOKEN_REQUIRED` / `TOKEN_INVALID`. Skip / Cancel / Relaunch revoke the *current*
  activation's token (Relaunch then mints a new invocation/activation). Every delivery is
  persisted as `outputs/<name>.<ordinal>.md` (collision-free by construction, even when
  several steps produce the same output name); `outputs/<name>.md` is the "latest" view,
  replaced atomically (temp file + rename); `run.json` records the invocation → step /
  iteration / activation / file mapping.
- Output bodies are capped (default 1 MiB, hard max 4 MiB → `OUTPUT_TOO_LARGE`).
- **Skip rule.** Skipping an `expect` (panel Skip or `on_timeout: skip`) marks its output
  missing. If any later step's template references that output (or the `until` of an
  enclosing `repeat` depends on its verdict), the run ends as `skipped` instead of
  advancing — V1 has no optional template values. The panel states which step depends on
  the output before the user confirms Skip; the validator warns when `on_timeout: skip`
  would end the run this way.
- Waiting is supervised by the state-driven watchdog (§10), not by wall-clock time; a
  `working` role is never interrupted.

## 6. Template variables (whitelist; substitution only)

| Variable | Value |
| --- | --- |
| `run.id`, `run.dir` | run UUID, `<root>/.prowl/workflow-runs/<run-id>` |
| `worktree.path`, `worktree.name`, `worktree.branch` | source worktree |
| `roles.<r>.name`, `roles.<r>.agent`, `roles.<r>.pane` | `launch`: frozen profile display name, agent token, pane short handle (`p12`) once launched — referencing `pane` before the role's `launch` step is a validation error. `current` / `pick`: the pane's launch-profile name when Prowl launched it, otherwise the detected agent's display name (or `shell` when none); `agent` is the detected token or empty. |
| `outputs.<name>.path`, `outputs.<name>.verdict` | latest delivered output; referencing an output before any step can have produced it is a validation error |
| `actions.<step>.<key>` | native action outputs; `<step>` must be an `action` step, `<key>` a key declared by that action's registry schema, and the producer must dominate the reference in control flow (earlier in the same sequence; inside `repeat`, earlier in the same iteration body or outside the loop before it) — otherwise `WORKFLOW_INVALID` |
| `inputs.<k>` | start inputs |
| `loop.index`, `loop.count` | 1-based iteration inside `repeat`; `loop.count` = iterations completed (usable after the loop; `0` when the pre-entry `until` check skipped the loop) |

No expressions, defaults, or inlined output text (`outputs.<name>.text` does not exist).

## 7. Validation (`prowl workflow validate`, Settings status)

Errors: unknown `schema`/keys; undefined role; `kind: headless` (reserved); `message` to
a `launch` role before its `launch` step; a `launch` role launched twice; `close` of a
non-`launch` role; `expect` on `action` / `notify` / `close`; duplicate step ids; `repeat`
without `max`, nested `repeat`, or `launch` inside `repeat`; `until` referencing an
undeclared verdict; unknown template variable or premature `outputs.*` / `roles.<r>.pane` /
`actions.<step>.<key>` reference (unknown action step, undeclared key, or a producer that
does not dominate the consumer); unknown `action` id or `with` keys violating the action's
schema; `repeat.max` that is neither a positive integer literal in `1…20` nor a template
of exactly one `integer` input; `text` containing a line terminator; a string input default
containing a line terminator or control character; `skill` that does not match the
workflow-id pattern or does not resolve to a bundled skill; `verdict` with fewer than 2 or
more than 4 values, duplicate values, or a value that is not a safe slug; an `until`
literal outside the declared set; user file using a `prowl.` id; more than one `current`
role; ids that are not safe slugs — workflow `id` and `skill` ids must match
`^[a-z0-9][a-z0-9_.-]{0,63}$` (a leading alphanumeric rules out `.`/`..`); step ids, role
names, output names, input names, and verdict values must match
`^[a-z0-9][a-z0-9_-]{0,63}$` — because they become path components and CLI arguments.
Warnings: no installed agent satisfies `agents`; no enabled profile matches `suggest`;
`timeout` above 2h; `text`/`instruction` spelling out `prowl workflow done` (the runner
appends the rendered command itself); `on_timeout: skip` on an output referenced later.

## 8. Run directory

```
<root>/.prowl/workflow-runs/<run-id>/
  run.json                  # state snapshot: workflow id/version, frozen role bindings (profile UUID/name, pane ids),
                            # step states, timestamps; no env values, no extra arguments, no credentials
  log.md                    # human-readable, append-only
  instructions/<step>.<ordinal>.md   # materialized `instruction` / `prompt` text, one per invocation (run-global ordinal, §5)
  skills/<id>/SKILL.md      # materialized bundled skills
  outputs/<name>.md         # latest validated delivery (atomically replaced); every delivery is also kept as <name>.<ordinal>.md
```

`<root>/.prowl/workflow-runs/.gitignore` contains `*` (self-ignoring, as `.prowl/handoff/`).
Definitions shipped with a repo live in `<root>/.prowl/workflows/` (not ignored).

Safety: the run directory and every file below it are created only from validated slugs
and the run UUID, under canonical containment checks against
`<root>/.prowl/workflow-runs/` (no symlink leaf, resolved parent + leaf compared to the
resolved base — the `AgentProfileHomeProvisioner` gate). Repo-scoped definitions are
untrusted input; nothing from a workflow file is interpolated into a path except validated
slugs. Outputs are agent-authored content persisted at the agent's request (size caps in
§5); they are kept until the user removes the run folder (retention policy: V2). Privacy
wording as in §10: Prowl-authored persisted and response metadata (`run.json`, `log.md`,
the non-body fields of CLI payloads) carries profile UUID/name and agent tokens only —
never extra arguments, environment values, home paths, or credentials; the agent-provided
output body is excluded from that claim.

## 9. CLI participant protocol

```bash
prowl workflow list [--json]                                  # sources, enabled, validation status
prowl workflow run <id|name> [source] [--role r=<binding>]... [--input k=v]... [--json]   # <binding> grammar is source-specific, see below
                                                              # [source]: 060 GenericTarget (pN | tN | UUID | worktree ref); omitted → caller pane
                                                              # when the workflow has a `current` role (SOURCE_REQUIRED outside a pane), a
                                                              # worktree reference otherwise
prowl workflow status [run-id] [--json]                       # no args: "who am I" — caller pane's run, role, awaited step and its requirements
prowl workflow done [-|--file <path>] [--verdict <v>] [--token <token>] [--run <id> --step <id>] [--force] [--json]
prowl workflow cancel <run-id> [--json]
prowl workflow validate <file> [--json]
prowl workflow schema                                         # JSON Schema / reference for authoring agents
```

**Resolution of `done`.** Two independent facts must agree: the **caller pane** (socket
peer PID → process ancestry → shell PID → pane) identifies the run and role, and the
**delivery token** (`PROWL_WORKFLOW_TOKEN`, read from the environment of the `prowl`
process exactly like `PROWL_HANDOFF_REQUEST_ID` today, or `--token`) identifies the awaited
step. Prowl mints the token when the step starts waiting, embeds it in the typed hint, and
revokes it on Skip / Cancel / Relaunch; a stale or duplicated `done` from a pane that has
moved on to another step is therefore rejected instead of misattributed. A pane belongs
to at most one run at a time, so no run/step ids are needed in the typed command. Explicit
`--run --step` is required when no caller pane exists (manual delivery, logged as
`source=manual`, no token needed): it targets the step's *current* activation and is
attributed to that activation's delivery role; if the step is not currently waiting the
result is `STEP_NOT_EXPECTING`. If caller pane and explicit ids disagree,
`ROLE_MISMATCH` unless `--force`. Launched surfaces may additionally carry
`PROWL_WORKFLOW_RUN` / `PROWL_WORKFLOW_ROLE` as a cross-check hint; the registry is the
authority.

**`--role` grammar** (source-specific; duplicate overrides for one role and overrides for
unknown roles are `INVALID_ARGUMENT`; a missing override falls back to binding resolution):

```text
--role <launch-role>=<profile name | profile UUID | auto>
--role <pick-role>=<pN | pane UUID>        # must be a detected agent pane in the source worktree, not in another run (PANE_BUSY), not the current pane
# current roles take no override
```

The `run` response records every frozen binding (launch: profile id/name/agent; pick:
pane id/handle and detected agent).

Error codes: `WORKFLOW_NOT_FOUND`, `WORKFLOW_INVALID`, `RUN_NOT_FOUND`, `PANE_BUSY`,
`ROLE_MISMATCH`, `STEP_NOT_EXPECTING`, `TOKEN_REQUIRED`, `TOKEN_INVALID`,
`OUTPUT_INVALID` (sections/format/verdict), `OUTPUT_TOO_LARGE`, `VERDICT_REQUIRED`,
`PROFILE_NOT_FOUND`, `PROFILE_NOT_UNIQUE`, `SKILL_NOT_FOUND`, `RENDERED_TEXT_INVALID`
(a rendered `text`/pointer/`--input` value would not survive as one terminal line),
`UNSAFE_PATH`. (`AGENT_GONE` and `WAIT_TIMEOUT` belong to the `agents wait` contract, not
to `prowl workflow`.)

Companion primitives for CLI-driven orchestration (same boundaries as the runner):
`prowl create pane <pane> --direction <dir> [--profile <name|uuid> --prompt -]`,
`prowl create tab <worktree> [--profile … --prompt -]`, `prowl profiles list`,
`prowl agents wait <pane> --until idle|done|blocked|changed [--timeout]`, `prowl send`,
`prowl agents read`. `agents wait` consumes the typed per-surface observer
(`ObservedAgentState`: `snapshot` first, then `changed` / `removed` / `surfaceClosed`);
it returns immediately when the snapshot already satisfies `--until`, and maps `removed`
/ `surfaceClosed` to the terminal error `AGENT_GONE` (never to `done`) unless `--until
changed` was requested.

## 10. Run semantics

| Topic | Rule |
| --- | --- |
| Start | Resolve bindings, freeze plans, create run dir, write `run.json`, then execute step 1. `current` role must not already be in a run (`PANE_BUSY`). |
| Advance | A step completes when its `expect` is satisfied (or it has none and its effect succeeded). `repeat` evaluates `until` before entry and after each iteration; `max` reached with `until` still false ends the run as `max_rounds_reached`. |
| Message delivery | Injection is synchronous (`insertCommittedText` + submit); Prowl keeps no queue — a `working` agent holds the line in its own input queue, and the panel says so. A `message` step advances only after a successful injection; a `blocked` role, a missing surface, or a failed injection leaves the step active in `needsAttention` (Retry / Skip / Cancel). At most one pending injection per role; Cancel / Skip / Relaunch drop it. |
| Binding scope | As defined in §3 (four-tuple key with the canonical role-requirements digest); §3 is normative. |
| Invocation / activation | Defined in §5: every `message`/`launch` execution mints a run-global invocation ordinal (artifact naming); a waiting invocation is an activation with its own token; one delivery per activation; revocation is per activation; outputs and instructions are versioned by ordinal. |
| Rendered-text boundary | Every string that reaches `insertCommittedText` + submit — rendered `text`, pointer lines, completion commands, nudges — is validated after template substitution: no line terminators (`\n`, `\r`, U+2028/2029) and no C0/C1 control characters; violations stop the step with `RENDERED_TEXT_INVALID` (`needsAttention`, never a partial injection). String inputs and `--input` values are validated the same way at start; a worktree path that cannot be rendered on one line is rejected at start (`UNSAFE_PATH`). Multi-line content always goes through `instruction` / materialized files. |
| Watchdog | Driven by the periodic detection events (`agentEntryChanged` / `agentEntryRemoved`, forwarded to the runner by `AppFeature`'s single terminal-event subscription — `WorktreeTerminalManager.eventStream()` is single-consumer) plus an injected clock. When a step starts waiting the watchdog reads the role's current state first and schedules cancellable grace deadlines; it never depends on a later event alone. Every trigger has a grace period because detection is heuristic and a wrong guess must be harmless. Awaited role `blocked` ≥ `blocked_grace` (default 30 s) → `needsAttention` (Focus pane / Cancel). Awaited role `idle`/`done` ≥ `idle_grace` (default 3 min) without `done` → one automatic nudge (`[Prowl] When your work for this step is fully complete, finish with: <the active activation's completion command, from the §4 renderer — token and verdict choices included>`, harmless if the agent is still working because the runtime merely queues the line), then `needsAttention` after another `idle_grace` (Nudge again / Keep waiting / Skip / Cancel). Awaited role's agent process gone → `needsAttention` (Relaunch role / Skip / Cancel). `working` never triggers anything. Grace values are global settings. |
| `needsAttention` | A UI state (orange status slot + notification), never a deadline: a late `done` is still accepted; only an explicit Skip marks the output missing and rejects later deliveries. |
| Explicit `timeout` | Only when an author sets `expect.timeout`: `attention` (default) enters `needsAttention`; `skip` / `cancel` act automatically. |
| Cancel | Stops advancing and injecting; keeps all panes and outputs; logs. |
| Failure | Launch/plan/provision failure → `needsAttention` with Retry / Skip role / Cancel; outputs already delivered are kept. |
| Concurrency | One run per pane; many runs per worktree; the status center shows the selected worktree's most recent active run, the panel lists all. |
| Restart | V1: runs found on disk at launch are marked `interrupted`; no resume. |
| Privacy | Prowl-authored response metadata and persisted metadata (`run.json`, logs, the non-body fields of CLI payloads) carry profile UUID/name and agent tokens only — never extra arguments, environment values, home paths, or credentials. The agent-provided output body of `workflow done` is explicitly excluded from that claim: it is persisted as delivered, under the self-ignored run directory, within the size caps of §5. |

## 11. Built-in workflows (V1)

- `prowl.handoff` — roles `source: current`, `receiver: launch` (`placement: tab`,
  `background: true`, no `agents` restriction — any adapter with seeded-prompt support);
  steps: `message source` (brief, sections `## Objective`, `## Current State`,
  `## Next Steps`) → `action handoff.transition` (archive-first `.prowl/handoff/`
  contract) → `launch receiver` (`prompt: "{{ actions.transition.kickoff_prompt }}"`) →
  `notify`. The deprecated `prowl handoff` commands are served by a `LegacyHandoffAdapter`
  that maps `to <agent>` → Recommended enabled profile of that runtime (else
  `PROFILE_NOT_FOUND`), source selectors → run source, `--brief -` / `--no-brief` → `brief`
  output pre-delivered / step pre-skipped, `--note` → `handoff.transition` input,
  `--no-launch` → `launch` step pre-skipped with the target token recorded (no profile
  needed), `save` → `prowl.handoff-checkpoint` (brief → `action handoff.checkpoint`). The
  adapter **preflights before creating any run or artifact**, reproducing the current
  handler's immediate errors: neither `--brief` nor `--no-brief` → `BRIEF_REQUIRED` (the
  legacy path never starts an agent-mediated brief step or a hidden model turn); empty
  stdin → `EMPTY_INPUT`; a briefing missing the required sections → `INVALID_BRIEF`;
  unknown agent token → the existing argument error. With the `brief` step pre-supplied or
  pre-skipped the `current` role needs no detected agent, so a bare shell pane stays a
  valid legacy source. Action/transition failures map to the documented legacy failure
  response (never an attention state or partial success). The adapter starts the run with
  `failurePolicy: .fail`: a provisioning/launch failure after the artifacts are written
  ends the run as `failed` (artifacts and log kept) and returns `HANDOFF_FAILED`
  immediately, as the current handler does. It awaits run completion synchronously and
  renders the existing `prowl.cli.handoff.v2` response shape (schema-compatible;
  differences documented and covered by per-field socket parity tests: no-agent source,
  `--no-brief`, `--no-launch`, omitted brief choice → `BRIEF_REQUIRED`, empty stdin →
  `EMPTY_INPUT`, invalid sections → `INVALID_BRIEF`, action/transition failure, profile
  lookup failure, provisioning failure, launch failure).
- `prowl.adversarial-review` — as in §4; interactive reviewer in a right split by default.

## 12. Reserved for V2

`when:` (conditions on verdicts), `count:` / `wait: { all: […] }` (fan-out),
`expect.status: idle` + `capture: result` (observe mode via `agents read`), `kind:
headless` roles backed by a specified `HeadlessAgentExecutor` (cwd/env, stdout/stderr
bounds, exit/cancel/timeout semantics, per-runtime trusted result extraction), `worktree:`
on roles (cross-repo review), run resume, output retention policy, nested `repeat`,
`outputs.<name>.json` field access, custom (non-bundled) `skill:` sources with their own
rooted discovery and containment rules, `expect … from: <role>` on native actions.
