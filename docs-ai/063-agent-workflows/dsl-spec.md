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
  focus:      { type: string,  default: "", prompt: "What should the reviewer focus on?" }
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
    source: current                  # the pane the run was started from; must have a detected agent
  reviewer:
    source: launch                   # Prowl starts a new agent for this role
    kind: interactive                # interactive (default) | headless
    agents: [codex, claude]          # optional allow-list of agent tokens (as in `prowl agents` `type`); omitted = any launchable
    suggest:                         # optional; match an existing enabled profile exactly, or offer to create one
      agent: codex
      reasoning_effort: xhigh
      execution_mode: standard
    bind: ask                        # ask (default) | auto
    placement: split                 # split | tab (default: split for interactive, tab for headless)
    direction: right                 # right | left | up | down (split only)
    background: false                # true = do not focus/select the new surface
  partner:
    source: pick                     # an existing detected agent pane chosen at start (CLI: --role partner=p12)
```

| Field | Rules |
| --- | --- |
| `source` | Exactly one `current` role per workflow (optional: a workflow may have none, then it needs no detected agent at the entry). `pick` roles are chosen from `prowl agents` at start. |
| `kind` | Only for `launch`. `headless` roles accept a single `launch` step, cannot receive `message`, and deliver their captured output automatically. |
| `agents` | Tokens from the detected-agent catalog. Validator warns (not errors) when none is installed locally. |
| `suggest` | Subset of profile preset fields (`agent`, `model`, `reasoning_effort`, `execution_mode`). Never a reference to a profile name or UUID. |
| `bind` | `ask`: the start sheet always shows the role picker (pre-filled). `auto`: the sheet appears only when resolution is ambiguous. |

**Binding resolution** (per `launch` role, at start, in order): remembered local binding
`(workflow id, role) → profile UUID` → enabled profile matching `suggest` exactly →
Recommended profile (053 rules) filtered by `agents` → ask. The chosen profile is frozen
into the run together with its launch plan; later profile edits do not affect the run.
`--role <role>=<profile name|uuid|auto>` overrides from the CLI.

## 4. Steps

Each step has `id` (unique within the workflow), optional `title` (templated; shown in the
status center and panel), exactly one verb, and an optional `expect` (§5).

```yaml
steps:
  - id: brief
    title: "Author writing the brief"
    message: author                          # ① speak to a live interactive role
    instruction: |                           #    multi-line → materialized to run.dir/instructions/brief.md; one pointer line is typed
      Write a short brief for an adversarial reviewer: ## Scope, ## Claims, ## How to verify.
      When done: prowl workflow done -
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
        text: "Findings: {{ outputs.findings.path }}. Fix or rebut each, commit, then `prowl workflow done -` with your disposition."
        expect: { output: disposition, timeout: 30m }
      - id: rereview
        title: "Round {{ loop.index }}: reviewer re-checking"
        message: reviewer
        text: "Disposition: {{ outputs.disposition.path }}. Re-review the new commits; `prowl workflow done --verdict clean|issues -`."
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
| `message: <role>` | `text` (single line, typed verbatim) **or** `instruction` (multi-line, materialized + pointer) | live interactive role (`current`, `pick`, or a `launch` role already launched) | Injection is gated: `blocked` → not typed, run → `needsAttention`; `working` → queued, shown in the panel. |
| `launch: <role>` | `prompt` (kickoff, templated), optional `skill` | `launch` role, at most once per run (V1) | Interactive: profile plan with `AgentStartIntent.prompt`; headless: adapter one-shot with captured output. A single-line `prompt` is passed verbatim; a multi-line one is materialized and the kickoff becomes the pointer line. |
| `action: <id>` | `with` (templated map) | — | V1 registry: `handoff.transition` (inputs `briefing?`, `from`, `to`; performs archive-first `.prowl/handoff/` transition; outputs `kickoff_prompt`, `artifact_path`, `has_briefing`), `handoff.checkpoint`, `git.context`. |
| `notify: <text>` | — | — | Bell pipeline; click focuses the `current` role's pane. |
| `close: <role>` | — | `launch` roles | Never implicit; cancel never closes panes. |
| `repeat` | `max` (required), `until` (optional), `steps` | — | `until` compares a declared verdict only: `outputs.<name>.verdict == <value>` or `in [..]`. Reaching `max` without `until` ends the run as `max_rounds_reached`. |

**Typed line formats.** Every line Prowl types into a pane starts with `[Prowl] ` so its
origin is visible. `text` → `[Prowl] <text>`; `instruction` → `[Prowl] Read <absolute
path> and follow it`. When the step has an `expect`, the runner appends the completion
hint itself — ` — finish with: prowl workflow done [--verdict a|b] -` — so authors never
repeat it. The watchdog nudge is `[Prowl] When your work for this step is fully complete,
finish with: prowl workflow done -`.

## 5. `expect`

```yaml
expect:
  output: findings          # output name; default = step id; the same name may be produced by several steps (latest wins)
  format: markdown          # markdown (default) | text | json (parseable)
  sections: ["## Findings"] # markdown: required headings (fence/preamble stripped before checking, as HandoffStore.validatedBriefing)
  verdict: [clean, issues]  # declares allowed values; `prowl workflow done --verdict <v>` then becomes mandatory
  timeout: 2h               # optional hard cap; NO default — without it Prowl waits as long as the agent works
  on_timeout: attention     # only with `timeout`: attention (default) | skip | cancel
```

- A `launch` step of a `headless` role may omit `expect`; the captured output is stored
  under `outputs.<step id>` (or `expect.output` if given).
- Exactly one successful `done` is accepted per (run, step); later ones get `STEP_NOT_EXPECTING`.
- Waiting is supervised by the state-driven watchdog (§10), not by wall-clock time; a
  `working` role is never interrupted.

## 6. Template variables (whitelist; substitution only)

| Variable | Value |
| --- | --- |
| `run.id`, `run.dir` | run UUID, `<root>/.prowl/workflow-runs/<run-id>` |
| `worktree.path`, `worktree.name`, `worktree.branch` | source worktree |
| `roles.<r>.name`, `roles.<r>.agent`, `roles.<r>.pane` | frozen profile display name, agent token, pane short handle (`p12`) |
| `outputs.<name>.path`, `outputs.<name>.verdict` | latest delivered output; referencing an output before any step can have produced it is a validation error |
| `actions.<step>.<key>` | native action outputs |
| `inputs.<k>` | start inputs |
| `loop.index`, `loop.count` | 1-based iteration inside `repeat`; `loop.count` = iterations completed (usable after the loop) |

No expressions, defaults, or inlined output text (`outputs.<name>.text` does not exist).

## 7. Validation (`prowl workflow validate`, Settings status)

Errors: unknown `schema`/keys; undefined role; `message` to a `headless` role or to a
`launch` role before its `launch` step; a `launch` role launched twice; `close` of a
non-`launch` role; duplicate step ids; `repeat` without `max`, nested `repeat`, or `launch`
inside `repeat`; `until` referencing an undeclared verdict; unknown template variable or
premature `outputs.*` reference; `text` containing a newline; user file using a `prowl.` id;
more than one `current` role.
Warnings: no installed agent satisfies `agents`; no enabled profile matches `suggest`;
`timeout` above 2h.

## 8. Run directory

```
<root>/.prowl/workflow-runs/<run-id>/
  run.json                  # state snapshot: workflow id/version, frozen role bindings (profile UUID/name, pane ids),
                            # step states, timestamps; no env values, no extra arguments, no credentials
  log.md                    # human-readable, append-only
  instructions/<step>.md    # materialized `instruction` / `prompt` text
  skills/<id>/SKILL.md      # materialized bundled skills
  outputs/<name>.md         # validated deliveries; inside `repeat` versioned as <name>.<iteration>.md, latest symlink/copy
  captures/<step>.md        # headless captures
```

`<root>/.prowl/workflow-runs/.gitignore` contains `*` (self-ignoring, as `.prowl/handoff/`).
Definitions shipped with a repo live in `<root>/.prowl/workflows/` (not ignored).

## 9. CLI participant protocol

```bash
prowl workflow list [--json]                                  # sources, enabled, validation status
prowl workflow run <id|name> [source] [--role r=<profile|uuid|auto>]... [--input k=v]... [--json]
prowl workflow status [run-id] [--json]                       # no args: "who am I" — caller pane's run, role, awaited step and its requirements
prowl workflow done [-|--file <path>] [--verdict <v>] [--run <id> --step <id>] [--force] [--json]
prowl workflow cancel <run-id> [--json]
prowl workflow validate <file> [--json]
prowl workflow schema                                         # JSON Schema / reference for authoring agents
```

**Resolution of `done`.** The caller pane (socket peer PID → process ancestry → shell PID
→ pane) identifies the run, role, and awaited step. A pane belongs to at most one run at a
time, so no ids are needed in the typed command. Explicit `--run --step` is required when no
caller pane exists (manual delivery, logged as `source=manual`); if both exist and disagree,
`ROLE_MISMATCH` unless `--force`. Launched surfaces may additionally carry
`PROWL_WORKFLOW_RUN` / `PROWL_WORKFLOW_ROLE` as a cross-check hint; the registry is the
authority.

Error codes: `WORKFLOW_NOT_FOUND`, `WORKFLOW_INVALID`, `RUN_NOT_FOUND`, `PANE_BUSY`,
`ROLE_MISMATCH`, `STEP_NOT_EXPECTING`, `OUTPUT_INVALID` (sections/format/verdict),
`VERDICT_REQUIRED`.

Companion primitives for CLI-driven orchestration (same boundaries as the runner):
`prowl create pane <pane> --direction <dir> [--profile <name|uuid> --prompt -]`,
`prowl create tab <worktree> [--profile … --prompt -]`, `prowl profiles list`,
`prowl agents wait <pane> --until idle|done|blocked [--timeout]`, `prowl send`,
`prowl agents read`.

## 10. Run semantics

| Topic | Rule |
| --- | --- |
| Start | Resolve bindings, freeze plans, create run dir, write `run.json`, then execute step 1. `current` role must not already be in a run (`PANE_BUSY`). |
| Advance | A step completes when its `expect` is satisfied (or it has none). `repeat` re-evaluates `until` after each iteration. |
| Watchdog | Driven by the periodic detection events (`agentEntryChanged` / `agentEntryRemoved`) plus an injected clock; every trigger has a grace period because detection is heuristic and a wrong guess must be harmless. Awaited role `blocked` ≥ `blocked_grace` (default 30 s) → `needsAttention` (Focus pane / Cancel). Awaited role `idle`/`done` ≥ `idle_grace` (default 3 min) without `done` → one automatic nudge (`[Prowl] When your work for this step is fully complete, finish with: prowl workflow done -`, which merely queues if the agent is still working), then `needsAttention` after another `idle_grace` (Nudge again / Keep waiting / Skip / Cancel). Awaited role's agent process gone → `needsAttention` (Relaunch role / Skip / Cancel). `working` never triggers anything. Grace values are global settings. |
| `needsAttention` | A UI state (orange status slot + notification), never a deadline: a late `done` is still accepted; only an explicit Skip marks the output missing and rejects later deliveries. |
| Explicit `timeout` | Only when an author sets `expect.timeout`: `attention` (default) enters `needsAttention`; `skip` / `cancel` act automatically. |
| Cancel | Stops advancing and injecting; keeps all panes and outputs; logs. |
| Failure | Launch/plan/provision failure → `needsAttention` with Retry / Skip role / Cancel; outputs already delivered are kept. |
| Concurrency | One run per pane; many runs per worktree; the status center shows the selected worktree's most recent active run, the panel lists all. |
| Restart | V1: runs found on disk at launch are marked `interrupted`; no resume. |
| Privacy | `run.json`, logs, and CLI payloads carry profile UUID/name and agent tokens only. |

## 11. Built-in workflows (V1)

- `prowl.handoff` — roles `source: current`, `receiver: launch` (`placement: tab`,
  `background: true`, no `agents` restriction — any adapter with seeded-prompt support);
  steps: `message source` (brief, sections `## Objective`, `## Current State`,
  `## Next Steps`) → `action handoff.transition` (archive-first `.prowl/handoff/`
  contract) → `launch receiver` (`prompt: "{{ actions.transition.kickoff_prompt }}"`) →
  `notify`. `prowl handoff to <agent> --brief -` remains as a deprecated alias that starts
  this run with the `brief` output pre-delivered (`--no-brief`: step pre-skipped);
  `prowl handoff save` maps to `prowl.handoff-checkpoint` (brief → `action
  handoff.checkpoint`).
- `prowl.adversarial-review` — as in §4; interactive reviewer in a right split by default.

## 12. Reserved for V2

`when:` (conditions on verdicts), `count:` / `wait: { all: […] }` (fan-out),
`expect.status: idle` + `capture: result` (observe mode via `agents read`), `worktree:` on
roles (cross-repo review), run resume, nested `repeat`, `outputs.<name>.json` field access.
