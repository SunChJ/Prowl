# 063 — Agent Workflows: Plan

| | |
| --- | --- |
| **Status** | Planned (design in discussion; see Open questions) |
| **Anchor date** | 2026-08-21 |
| **Primary PRs** | TBD (see Delivery slicing) |
| **Related** | [047 cross-agent-handoff](../047-cross-agent-handoff/000-plan.md), [049 agents-toolbar-entry](../049-agents-toolbar-entry/000-plan.md), [053 agent-profiles](../053-agent-profiles/000-plan.md), [055 agent-profile-runtimes](../055-agent-profile-runtimes/000-plan.md), [059 agent-transcript-snapshots](../059-agent-transcript-snapshots/000-plan.md), [060 cli-targeting-and-contract-governance](../060-prowl-cli-targeting-and-contract-governance/000-plan.md), [061 native-toolbar-controls](../061-native-toolbar-controls/toolbar-controls.md), [#699 `prowl create pane`](https://github.com/onevcat/Prowl/issues/699), [PR #651 (direction reference, not merged)](https://github.com/onevcat/Prowl/pull/651), [DSL spec (living)](dsl-spec.md), `docs/components/handoff.md`, `docs/components/agent-profiles.md`, `docs/components/cli.md` |

## Background

Prowl already runs several coding agents side by side, identifies them per pane, launches
them through Agent Profiles (053/055), reads their trustworthy results (059), and hands a
task from one agent to another (047/049). The handoff that exists today is valuable but
structurally stuck:

- Its flow is a fixed state machine (`HandoffStage` `requesting → finishing`,
  `HandoffHudPhase` choose/run/finish in
  `supacode/Features/HandoffHud/Reducer/HandoffHudFeature.swift`); target list, briefing
  sections, kickoff prompt, and injection text are literals
  (`supacode/CLIService/Shared/HandoffAgentSupport.swift`,
  `supacode/CLIService/HandoffCommandHandler.swift`,
  `supacode/Domain/Handoff/HandoffInjection.swift`).
- Its two launch paths (CLI → `WorktreeTerminalState.createTab(initialInput:)`, HUD
  fallback → `TerminalClient.Command.createTabWithInput`) bypass Agent Profiles entirely:
  `AgentStartRequest.dedicatedHome` is always nil, and model/effort/extra arguments/env
  never reach the receiver. PR #651 tried to thread a profile UUID through that fixed flow;
  the direction (profile-bound receiver, freeze before commit, one shared launch boundary
  returning exact pane identity, no secrets in artifacts) is right, the shape is not.
- The orchestration onevcat actually runs day to day — agent 1 opens a split, launches
  agent 2 with a prompt, monitors it, reads its result, fixes, asks for another round until
  clean — lives only in ad-hoc `prowl` CLI usage and cannot be reproduced or shared.

The foundations that make a general solution possible are all on `main` now: a pure
profile launch planner with a typed `.prompt` start intent
(`supacode/Domain/AgentProfile/AgentProfileLaunchPlan.swift`,
`supacode/Domain/AgentRuntime/AgentRuntimeAdapter.swift`), text injection into a live pane
(`TerminalClient.sendTextToSurface`), caller-pane identity for CLI calls
(`supacode/CLIService/CLICommandContext.swift`), one-shot request ownership
(`supacode/Domain/Handoff/HandoffRequestRegistry.swift`), briefing validation
(`HandoffStore.validatedBriefing`), the agent status event stream, a toolbar status slot
(`supacode/Features/Repositories/Views/ToolbarStatusView.swift`), and the four-layer CLI
contract governance of 060.

## Goals

- Replace the hard-coded handoff flow with **Agent Workflows**: data-driven, multi-agent
  orchestrations declared in a YAML DSL (`prowl.workflow/v1`, normative text in
  [dsl-spec.md](dsl-spec.md)) and executed by a reducer-owned runner inside Prowl.
- Make the orchestration onevcat runs by hand (launch reviewer in a split → review →
  fix → re-review until clean) expressible, reproducible, and shareable as a file.
- Bind workflow roles to Agent Profiles **without** coupling the file to a machine: a
  workflow declares abstract role requirements; the role → profile binding is local,
  remembered, and overridable.
- Surface runs in the toolbar's central status slot (`Adversarial Review · 3/6 · Round 2:
  reviewer re-checking`) with a popover for steps, role panes, and controls; keep every
  existing entry point (Agents capsule popover, Command Palette, Active Agents context menu).
- Let agents participate through the `prowl` CLI only (`prowl workflow done`), so every
  recognized runtime can play any interactive role, and keep the pure-CLI route (an agent
  orchestrating others by hand) first-class by shipping the missing primitives.
- Ship two built-in workflows — `prowl.handoff` (replacing the current implementation) and
  `prowl.adversarial-review` — plus bundled skills, and a documented path for users (and
  their agents) to author custom workflows.

### Non-goals

- A visual workflow editor. Authoring is YAML + `prowl workflow validate` + agent
  assistance (bundled docs/skill).
- General control flow (conditions, parallel fan-out, nesting) in V1. V1 control flow is
  sequential steps plus one bounded `repeat … until <verdict>` construct.
- Executing shell commands, writing arbitrary files, git/network operations, sending
  keystrokes, or answering permission prompts from a workflow.
- Launching agents outside Agent Profiles. `suggest` may match or create a profile; it
  never bypasses one.
- Cross-worktree roles (all roles of a run live in the source worktree) and resuming runs
  across app restarts — both V2 candidates.
- Analytics for workflows; workflow ids, role bindings, and run content never enter
  PostHog/Sentry.

## Design / Approach

### Concepts

| Term | Meaning |
| --- | --- |
| Workflow | A `prowl.workflow/v1` YAML document: id, inputs, roles, steps. Sources: bundle (`prowl.*` ids), user (`~/.prowl/workflows/*.yaml`), repo (`<root>/.prowl/workflows/*.yaml`). |
| Role | A participant: `source: current` (the pane the run was started from; it must host a detected agent only if the runner will actually deliver a `message` to it — steps pre-skipped or completed by a seeded output at start do not count — so a bare shell can still be the source of a context-only or pre-briefed handoff), `pick` (an existing detected agent pane in the same worktree, chosen at start), or `launch` (a new agent Prowl starts). V1 launch roles are interactive (TUI in a tab/split); `kind: headless` is reserved for V2 (see Alternatives). |
| Binding | Role → concrete Agent Profile (or, for `pick`, an existing pane), resolved at start and frozen into the run; the only exception is the internal destination-only binding the legacy handoff adapter uses for `--no-launch` (agent token, no profile). |
| Step | One verb: `message` (say something to a live role), `launch` (start a launch role), `action` (built-in Swift action), `notify`, `close`; plus `repeat` blocks. Each step has a `title` for the status slot and an optional `expect`. |
| Expect | Only on `message` / `launch` steps: what must happen before the run advances — a named `output` delivered by the step's target role via the generated `prowl workflow done` command, optional `sections`/`format` validation, optional `verdict` enum (safe slugs), optional `timeout` / `on_timeout`. |
| Run | One execution: state snapshot + artifacts under `<root>/.prowl/workflow-runs/<run-id>/`. |

### Execution model: Prowl runs, agents participate

The runner is a TCA feature (`WorkflowRunsFeature`, reducer-owned like the handoff HUD was)
that advances one step at a time through existing terminal boundaries:

- `launch` → the shared profile launch boundary (`launchAgentProfile` extended with
  `AgentStartIntent.prompt`, placement override, anchor surface, background, returning the
  created tab/surface identity — the #651 "shared terminal boundary" done properly).
- `message` → `TerminalClient.sendTextToSurface` into the role's pane, gated by detection.
  Injection is synchronous (insert + submit, no Prowl-side queue); a `working` agent
  receives the line in its own input queue (Claude Code and Codex queue typed input), and
  the panel says so. A `message` step advances only after a *successful* injection: if
  the role is `blocked`, its surface is gone, or injection fails, the step stays active in
  `needsAttention` (Retry / Skip / Cancel) — it never advances on a line that was not
  delivered. At most one pending injection exists per role; Cancel / Skip / Relaunch drop
  it.
- `expect` → a `WorkflowRequestRegistry` entry (generalizing `HandoffRequestRegistry`)
  keyed by an **opaque per-activation delivery token** (a UUID, hence shell-safe). Lifecycle
  (normative in the DSL spec §5): every `message`/`launch` execution mints a run-global
  invocation ordinal on entry; when the step has an `expect`, that invocation is an
  activation `(run, step, ordinal, role)` whose token is minted *before* the line is
  rendered and injected (the injected text carries it); every `repeat` iteration and every
  Retry/Relaunch is a new invocation. One delivery per activation. The token is placed in
  the generated completion command
  (`PROWL_WORKFLOW_TOKEN=<token> prowl workflow done -`, the same env-prefix technique as
  today's `PROWL_HANDOFF_REQUEST_ID`; `--token <token>` is the explicit form). The entry
  is claimable exactly once; a `done` that arrives without the token, with a revoked token
  (Skip / Cancel / Relaunch revoke), or from a pane other than the role's is rejected — so
  a delayed or duplicated `done` from a pane that has since moved on to another step can
  never be misattributed. Tokens are never written into YAML, and the **generated
  command is the only spelling agents ever see**: one completion-command renderer produces
  the initial hint, every nudge, and every re-delivery (token always present; for verdict
  steps one complete executable command per allowed value on every transport — typed
  line, materialized instruction, and `prowl workflow status` — never a placeholder);
  built-ins and examples say
  "finish with the generated completion command"; the validator warns when
  `text`/`instruction` spells out `prowl workflow done`. `expect` is valid only on
  `message` and `launch` (their target role delivers); native actions return typed
  outputs synchronously. Skipping a step whose expected output is referenced by a later
  template ends the run as `skipped` (the panel says which step depends on it) — V1 has
  no optional template values, so the alternative would be an unrenderable step. The one
  tolerated consumer is a `with` input declared optional by the action's schema: the key is
  simply absent, which is how skipping the brief turns `prowl.handoff` into a context-only
  transition (the old HUD's "Context Only" fallback, now a generic rule).
- `action` → a registry of native Swift actions (`handoff.transition`, `git.context`).
- `notify`/`close` → the existing bell pipeline and protected close path.

**Data channels.** Inbound to an agent is always *file + short pointer*: long
`instruction` text is materialized (one file per invocation, named by the run-global
invocation ordinal — the DSL spec §§5/8 are normative for run-directory layout) and one
line is typed (or passed as the kickoff prompt); short `text` is typed verbatim (single
line).
Outbound is `prowl workflow done [--verdict v] -` (stdin): the caller pane identifies the
run/role, the delivery token identifies the awaited step — the YAML itself carries nothing
machine-specific. Transcript observation (`agents read`) and headless adapter capture are
V2 channels (see Alternatives).

**Event topology.** `WorktreeTerminalManager.eventStream()` is single-consumer (a new
subscription finishes the previous stream) and `AppFeature` is its only subscriber. The
runner therefore lives as a child reducer of `AppFeature`, which forwards
`agentEntryChanged` / `agentEntryRemoved` / `taskStatusChanged` to it; nothing else
subscribes to `TerminalClient.events()`. `prowl agents wait` (and any other CLI observer)
uses a new per-surface multicast observer on `WorktreeTerminalManager`, independent of the
reducer stream and typed so that disappearance is observable:

```swift
enum ObservedAgentState: Sendable {
  case snapshot(ActiveAgentEntry?)   // always the first element, even when no agent is detected
  case changed(ActiveAgentEntry)
  case removed                       // agent process gone; entry removed (today: agentEntryRemoved)
  case surfaceClosed                 // pane closed; stream finishes after this
}
func observeAgentState(surfaceID: UUID) -> AsyncStream<ObservedAgentState>
```

Each subscriber gets its own bounded buffer (newest-wins coalescing, like
`TerminalEventCoalescer`); registration and snapshot capture happen in one main-actor
step so no change can fall between them, the snapshot precedes live events, cancellation
removes the subscriber, and `surfaceClosed` terminates the stream. `agents wait` maps `removed` /
`surfaceClosed` to a terminal `AGENT_GONE` error (not to `done`) unless `--until changed`
was requested. The runner's watchdog likewise reads the role's *current* state first and
schedules cancellable grace deadlines on the injected clock; it never relies on a later
event alone.

**Data bus.** `<root>/.prowl/workflow-runs/<run-id>/` holds `run.json`, `log.md`,
`instructions/` and `outputs/` (both versioned by the run-global invocation ordinal, latest
output view replaced atomically — layout normative in the DSL spec §8), `skills/`
(materialized from the embedded skill registry only — `skill:` ids are safe slugs that must
resolve to a bundled skill).
Distribution is "the next instruction names the path"; Prowl never inlines one agent's
output into another agent's input box, and every rendered line is re-validated as a
single terminal line before injection (template values such as inputs or paths cannot
smuggle a newline past the boundary). Outputs are agent-authored
content persisted at the agent's request — or, for the internal seeded outputs of the
legacy adapter, caller-supplied content validated against the step's `expect` — (default
cap 1 MiB, hard max 4 MiB,
`OUTPUT_TOO_LARGE` otherwise; same bounds as `agents read`), kept until the user deletes
the run folder (retention policy is a V2 item, as for `.prowl/handoff/archive`). Step ids
and output names are restricted to safe slugs because they become path components; run
directories are created with canonical containment checks under
`<root>/.prowl/workflow-runs/` (no symlink leaf), mirroring
`AgentProfileHomeProvisioner`. Repo-scoped workflow files are untrusted input and go
through the same validator.

**Binding resolution** (per `launch` role, at start): remembered binding → enabled
profile matching `suggest` exactly → 053's Recommended filtered by `agents` → ask. The
memory key is `(definition scope, workflow id, role, role-requirements digest)` where
scope is `bundle`, `user`, or `repo:<repository id>` and the digest covers the role's
requirement block (`source`, `kind`, `agents`, `suggest`) — so a repo workflow that
shadows a same-id user workflow, the same id in two repositories, two worktrees of one
repository carrying divergent definitions, or an edited role in a same-id file never
reuses a binding made for different requirements, while prompt-only edits keep it. Every
candidate (remembered
or `--role` override included) is re-validated before use: still exists, enabled,
satisfies `agents`, and its adapter supports the intent the role needs (seeded prompt);
otherwise resolution falls through to the next tier. The Start sheet shows a picker per
role with "Create profile from suggestion…" when nothing matches; `bind: auto` skips the
sheet when resolution is unambiguous. CLI overrides are source-specific (`--role
<launch-role>=<profile name|uuid|auto>`, `--role <pick-role>=<pN|pane UUID>`; see the DSL
spec §9).

**Waiting is state-driven, not wall-clock.** `expect` has no default timeout: a working
agent is never interrupted however long it takes. Instead the runner's watchdog consumes
the existing detection events (`agentEntryChanged` / `agentEntryRemoved`, produced by the
periodic detection schedule) with grace periods, because detection is heuristic and a
wrong guess must be harmless: a role `blocked` for ≥ `blocked_grace` (default 30 s) →
`needsAttention` (Focus pane / Cancel); a role `idle`/`done` for ≥ `idle_grace` (default
3 min) without `done` → Prowl **auto-nudges once** (types `[Prowl] When your work for this
step is fully complete, finish with: <the activation's rendered completion command — token
and, for verdict steps, one executable command per value>`, harmless if the agent was in
fact still working — the runtime just queues the line) and escalates to
`needsAttention` (Nudge again / Keep
waiting / Skip / Cancel) only after another `idle_grace`; the role's agent process
disappearing → `needsAttention` (Relaunch role / Skip / Cancel). `needsAttention` is a UI
state, never a deadline: a late `done` is still accepted. Grace values are global settings
(Settings › Workflows); an author may still add an explicit `expect.timeout` with
`on_timeout: attention|skip|cancel` for hard caps.

**Invariants** (carried from 047/053/#651): a pane belongs to at most one run at a time
(`PANE_BUSY`); injection only into panes bound to the run; roles and their plans are frozen
at start; `done` is accepted only from the bound pane with a live delivery token, unless an
explicit `--run/--step` (manual, logged) or `--force` is given; attention states wait for a
person, they never discard delivered outputs; cancel never closes a pane; Prowl-originated
metadata (requests, payloads, `run.json`, logs) never carries extra arguments, environment
values, home paths, or credentials — agent-authored outputs are the agents'
responsibility and stay under the self-ignored run directory; the runner performs no git
writes.

### UI

- **Status center**: `ToolbarStatusView` gains a `workflowRun` state with priority
  toast > active run of the selected worktree > PR > palette hint. The slot itself stays
  minimal — an animated running indicator plus the current step's `title` (orange
  attention glyph in `needsAttention`; a count badge when the worktree has several active
  runs) — because the principal item cannot carry more. Everything else lives in the
  hover-open/pin-on-click popover (same pattern as `PullRequestChecksPopoverButton` /
  `ToolbarNotificationsPopoverButton`): header (workflow, worktree, elapsed, state), role
  chips (profile icon + name + `pN`, click → focus), a height-capped **scrolling** step
  list (authors may declare any number of steps; `repeat` iterations grouped as `Round
  k/max`; the active step rendered as title + dimmed body with the full instruction
  text), the attention block with its actions (Focus pane / Nudge / Keep waiting / Skip /
  Relaunch / Cancel as applicable), and Cancel / Reveal run folder / Open log. Completion
  reuses the `success` toast. Notifications for attention and completion go through the
  bell with click-to-focus, silenced while the user watches that worktree. Detailed
  visual design is deferred to C1 (build-time, 061 visual verification). Follows 061: the
  principal slot stays a display item; no new glass exceptions.
- **Start sheet**: the centered HUD card pattern of the handoff HUD (keyboard-capturing,
  not window-modal) becomes `WorkflowStartOverlay`: title/description → "You: <agent> in
  pN" for the `current` role → one picker per `launch` role (filtered by `agents`,
  pre-selected, unavailable rows dimmed with reason, "Create from suggestion…" when
  nothing matches) → one pane picker per `pick` role (detected agents excluding panes
  already in a run and the current pane) → inputs → "Don't ask again for this workflow"
  (when `bind: ask`) → Cancel / Run. A CLI-not-installed banner with an inline Install
  action disables Run. `bind: auto` with unambiguous bindings and defaulted inputs skips
  the sheet.
- **Entry points**: Agents capsule popover gains a Workflows section (`Hand Off…` stays
  its first row); Command Palette `Run Workflow: <name>`; Active Agents row context menu
  `Run Workflow ▸` and an `in <workflow> · <role>` subtitle on rows that belong to a run.
  The start sheet replaces the handoff HUD's choose stage; the HUD's run/finish stages are
  subsumed by the status center (049's deferred PR2).
- **Settings information architecture**: the Agents star feature becomes a sidebar
  *group* (`Section("Agents")`, same native pattern as the Repositories group in
  `supacode/Features/Settings/Views/SettingsView.swift`) with three pages — **Profiles**
  (today's Agents page, renamed), **Workflows** (new), **Command Line Tool** (the `prowl`
  install/status/socket/"Ask your agent" entry, moved out of Advanced because agents are
  its primary consumer). Workflows ↔ Profiles stay linked by cross-reference, not by
  merging: each workflow row shows its role → profile bindings (editable, jump to
  Profiles); a CLI dependency banner with an inline Install action sits atop Workflows and
  the runner preflights CLI installation before a run. Workflows page contents: Built-in
  / User / Repo lists, enable toggle, per-workflow "ask for bindings" override, validation
  status with YAML line errors, Reveal, New Workflow… (template file), Ask your agent to
  write one (prompt pointing at bundled `docs/` + `skills/`).

### CLI (per 060's four-layer rule)

`prowl workflow list | run <id> [source] [--role r=…] [--input k=v] | status [run] | done
[-|--file] [--verdict v] [--token t] [--run --step] [--force] | cancel <run> | validate
<file> | schema` — `[source]` is 060's `GenericTarget` (`pN`, `tN`, UUID, worktree ref); omitted,
the source is the caller pane when the workflow has a `current` role, and a worktree
reference is required otherwise; `--role` is source-specific (`launch` role →
`<profile name|uuid|auto>`, `pick` role → `<pN|pane UUID>` in the source worktree,
`current` → none); `prowl profiles list` (read-only, for CLI-driven orchestration);
prerequisites
`prowl create pane <pane> --direction … [--profile <name|uuid> --prompt -]` (#699 extended)
and `prowl agents wait <pane> --until idle|done|blocked [--timeout]`. `prowl handoff
to|save` remain (see Open questions for alias vs. removal).

### Built-ins and distribution

- `Resources/workflows/*.yaml` and `Resources/skills/` are embedded like `docs/`
  (`Makefile` `embed-docs` pattern); `skill:` references are materialized into the run
  directory so sandboxed agents can read them.
- `prowl.adversarial-review`: interactive reviewer in a right split (transparency and user
  trust outweigh headless precision), `repeat … until outputs.findings.verdict == clean`
  with `max_rounds`.
- `prowl.handoff`: `message source` (brief) → `action handoff.transition` (keeps the
  `.prowl/handoff/` artifact contract; outputs `kickoff_prompt`, `artifact_path`,
  `has_briefing`) → `launch receiver` (background tab, prompt from the action output) →
  notify. The receiver role carries **no `agents:` restriction**: any runtime whose adapter
  supports a seeded prompt is admissible (055 verified all but Amp, which the adapter
  rejects itself); the 047-era claude/codex-only admission is retired. The deprecated
  `prowl handoff` commands are served by a **`LegacyHandoffAdapter`** in the app (D3) that
  maps every existing parameter onto the runner's internal start API and renders the
  existing `prowl.cli.handoff.v2` response shape (schema-compatible; semantic differences
  documented, not "byte-compatible"): `to <agent>` with a requested launch → the
  Recommended enabled profile of that runtime, else `PROFILE_NOT_FOUND` with guidance;
  `to <agent> --no-launch` → no profile lookup, the receiver role is frozen as a typed
  destination-only binding carrying the validated token and the `launch` step is
  pre-skipped (so `prowl handoff to gemini --no-launch` keeps its archive/log/`to_agent`
  behavior for every detected-agent token); source selectors / positional source → run
  source; `--brief -` → the `brief` step completed by a *seeded output* (validated in
  preflight, then materialized as a versioned `outputs/brief.<ordinal>.md` with a `seeded`
  record — no fabricated delivery or token; DSL spec §5); `--no-brief` → step pre-skipped
  (absent briefing = context-only transition: archive, remove the stale `current.md`,
  regenerate `context.md`, context-only kickoff); `--note` → `handoff.transition` input;
  `save` → `prowl.handoff-checkpoint`. The adapter
  preflights before any run or artifact exists, reproducing today's immediate errors
  (`BRIEF_REQUIRED` when neither `--brief` nor `--no-brief` is given — the legacy path
  never starts an agent-mediated brief step; `EMPTY_INPUT`; `INVALID_BRIEF`), and maps
  action/transition failures to the legacy failure response. Because the
  `brief` step is pre-supplied or pre-skipped, the `current` role needs no detected agent
  — a bare shell pane remains a valid legacy source, as today. The adapter starts the run
  with `failurePolicy: .fail` (the runner's generic `.attention` policy would hang a
  synchronous CLI call): a launch/provision failure after the artifacts are written ends
  the run as `failed`, keeps artifacts and log, and returns `HANDOFF_FAILED` exactly as the
  current handler does. The adapter awaits run completion synchronously (no agent wait is
  involved once the brief is supplied) and is covered by per-field socket parity tests
  (the DSL spec §11 list is normative: no-agent source, `--no-brief`, `--no-launch`,
  omitted brief choice, empty stdin, invalid sections, action/transition failure, profile
  lookup failure, provisioning failure, launch failure).
- `skills/prowl-workflows/SKILL.md`: how to author and run workflows; `prowl workflow
  schema` prints the machine-readable reference.

### Prerequisite interfaces (A1/A2) and test strategy

Shapes are intentionally close to what exists so the runner and the CLI share one boundary.

- **Anchored split primitive** (`supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift`):
  `createSplit(of anchorSurfaceID: UUID, direction:, initialInput:, additionalEnvironment:,
  focusing:) -> Result<UUID, SplitCreationError>` — the current
  `createSplitOnFocusedSurface` becomes a wrapper that resolves the focused surface and
  delegates. No focus-then-split (per #699).
- **Launch boundary** (`WorktreeTerminalState.swift`, `TerminalClient.swift`,
  `AgentProfileLaunchPlan.swift`): `AgentProfileLaunchPlanner.plan(for:intent:homeBaseDirectory:)`
  gains the intent (default `.interactive`; stays pure); a new
  `AgentProfileLaunchRequest { plan, placement: .tab(background:) | .split(anchor: UUID?,
  direction:), workingDirectoryOverride: URL?, title: String? }`;
  `WorktreeTerminalState.launchAgentProfile(_ request) -> Result<LaunchedSurface {tabID,
  surfaceID}, AgentProfileLaunchError>`; a synchronous result-returning `TerminalClient`
  closure (same style as `createTabInDirectory`), with the existing fire-and-forget
  `Command.launchAgentProfile(worktree, plan:)` kept as a wrapper that still emits
  `agentProfileLaunched` / `agentProfileLaunchFailed` for the menu/palette path.
- **CLI additions**: `CreateInput` gains `direction` and an optional `launch { profile:
  <name|uuid>, prompt: String? }`; `LifecycleCommandHandler` gains a `createPane` provider
  and a profile-launch provider; profile lookup is UUID first, then exact unique name
  (`PROFILE_NOT_FOUND` / `PROFILE_NOT_UNIQUE`); `prowl.cli.create.v1` is extended
  additively (`resource: pane`, `anchor`, `direction`, optional `launch {profile_id,
  profile_name, agent}`). `prowl profiles list` is a read-only snapshot of enabled/disabled
  profiles with availability (`prowl.cli.profiles.v1`). `prowl agents wait <pane> --until
  idle|done|blocked|changed --timeout 1…3600` consumes the typed `ObservedAgentState`
  observer described above (snapshot first → immediate return when already satisfied;
  `WAIT_TIMEOUT` on expiry; `removed` / `surfaceClosed` → error `AGENT_GONE` with the last
  known status in the error payload) and returns `{status, raw_state, waited_ms}`
  (`prowl.cli.agents.wait.v1`).
- **Tests**: terminal-layer coverage extends `supacodeTests/WorktreeTerminalStateAgentProfileTests.swift`
  (anchored split, placement override, background tab, returned identity, provisioning
  failure); planner intent rendering per adapter in `supacodeTests/AgentProfileTests.swift`
  / `AgentRuntimeAdapterTests.swift` (Amp rejects seeded prompts); handler coverage in
  `supacodeTests/CLILifecycleCommandHandlerTests.swift` and new handlers for `profiles
  list` / `agents wait` (TestClock for the timeout); parser tests beside
  `ProwlCLITests/AgentsCommandParsingTests.swift`; socket round trips plus schema validation
  in `ProwlCLITests/ProwlCLIIntegrationTests.swift`; contracts (`create.md`,
  `targeting.md`, new `profiles.md`, `agents-wait.md`), `docs/components/cli.md`, and the
  `prowl-cli` skill updated in the same PRs; the runner's own tests use fake
  `TerminalClient` closures, a temp run directory, and `TestClock` for the watchdog.

### Delivery slicing

Four tracks — terminal/CLI primitives (A), definitions/runner (B), UI (C), built-ins and
docs (D) — merged in the order below. C0 ∥ A1 ∥ B1 and A2 ∥ B2 can proceed in parallel.
Milestones: **M1** (C0+A1+B1+A2: CLI-driven orchestration usable, DSL authorable and
validatable), **M2** (B2+B3+C1+C2: engine and GUI run workflows), **M3** (D1+D2+D3:
built-ins land, handoff migrated).

| Order | PR | Track | Depends | Rationale |
| --- | --- | --- | --- | --- |
| 1 | **C0** Settings IA: Agents group (Profiles / Workflows placeholder / Command Line Tool moved from Advanced) | C | — | Independent, small, decides where everything lands |
| 2 | **A1** `prowl create pane` (#699) + target-surface split primitive returning the surface id; CLI four layers | A | 060 | Foundation for every `launch` into a split |
| 3 | **B1** Definitions: Yams, `AgentWorkflow` model + validator + JSON Schema, three-source discovery, `prowl workflow list/validate/schema`, read-only Settings list | B | — | Parallel with A1; makes the DSL concrete and authorable |
| 4 | **A2** Profile launch boundary (`.prompt`, placement override, anchor, background, synchronous `LaunchedSurface` result) + `prowl create tab/pane --profile --prompt -` + `prowl profiles list` + `prowl agents wait` | A | A1 | Unlocks the CLI-driven route and is the runner's `launch` boundary |
| 5 | **B2** Runner core (pure): run state machine incl. `repeat`, run store, template renderer, `WorkflowRequestRegistry`, action registry, watchdog with injected clock — tested against fake boundaries | B | B1 | Parallel with A2 |
| 6 | **B3** Runner wiring: `WorkflowRunsFeature` effects, detection-event subscription, CLI preflight, `prowl workflow run/status/done/cancel` + contracts | B | A2, B2 | Engine first powered on |
| 7 | **C1** Status center fifth state + run panel + attention triggers + notifications (061 visual verification) | C | B3 | Runs become visible |
| 8 | **C2** Start sheet (bindings, suggestion-based profile creation, don't-ask-again) + entry points (capsule popover, palette, Active Agents context menu) | C | B3 | GUI-initiated runs |
| 9 | **D1** `embed-skills`, `prowl-workflows` authoring skill, `docs/components/workflows.md`, Settings › Workflows complete (enable/validate/Reveal/New/Ask-agent/per-workflow auto) | D | B1, C2 | Distribution and docs |
| 10 | **D2** `prowl.adversarial-review` built-in + reviewer skill + E2E self-verification | D | A2, C2, D1 | Proves the engine on a fresh flow before touching shipped behavior |
| 11 | **D3** `prowl.handoff` built-in + `handoff.transition`; `prowl handoff` → deprecated alias; remove `HandoffHudFeature`; rewrite `docs/components/handoff.md` | D | D2 | Migrate the shipped feature last |
| 12 | V2: fan-out (`count`, `wait all`), observe mode (`agents read` capture), run persistence/resume, cross-worktree roles, GUI editor | — | — | — |

## Alternatives & decisions

- **Prowl-native runner, not an orchestrator agent.** A reducer-owned state machine is
  deterministic, observable in the toolbar, costs no extra model turns, and is the natural
  generalization of 047/049's "trigger + observer" HUD. The CLI-driven route stays possible
  (and is why #699/profile launch/`agents wait` are prerequisites), but it is not the
  product's main line.
- **YAML (Yams) as the source of truth; Mermaid render-only.** Multi-line prompts are the
  bulk of a workflow; block scalars are essential. JSON remains valid input. Parsing
  Mermaid into stable orchestration semantics is fragile and was rejected.
- **`done`-first outbound channel, not transcript observation.** `prowl workflow done` is
  runtime-agnostic, validated, correlated by caller pane + delivery token, and proven by
  the inline brief. `agents read` covers only Claude/Codex and depends on intermittent
  session attribution; it becomes a V2 assist.
- **Headless roles deferred to V2.** The adapters only *render* `.headless` invocations;
  there is no process executor, output protocol, or per-runtime trusted-result extraction
  yet (cwd/env, stdout/stderr bounds, exit/cancel/timeout semantics all undefined). Neither
  V1 built-in needs it, and the interactive reviewer is the product default anyway, so
  `kind: headless` stays a reserved key until a `HeadlessAgentExecutor` is specified.
- **File + pointer inbound; `text` for short lines.** Typed text is one line by
  construction (TUIs submit on newline; `ghostty_surface_text` is not bracketed paste).
  Long content is materialized; short messages are typed verbatim so users can see them.
- **Interactive reviewer by default.** Side-by-side visibility of the review happening is
  part of the product's trust model (onevcat, 2026-08-21); headless roles are a V2 item.
- **Roles reference requirements, never local profile names.** `agents:` (allowed
  runtimes) + `suggest:` (match-or-create) + remembered local bindings keep shared files
  portable while profiles remain the only launch authority (053 boundary intact).
- **`repeat … until <verdict>` in V1, no expression language.** The one loop onevcat's
  real flow needs is "re-review until clean"; termination reads a machine-declared
  `--verdict`, never prose. `max` is mandatory. `until` is evaluated **before entering and
  after every iteration** (while-loop semantics), so a first-round `clean` verdict skips
  the loop entirely.
- **Step completion is `prowl workflow done`, not `submit <name>`.** Prowl knows which
  step awaits which pane, so the agent names nothing; output names live in YAML
  (`expect.output`).
- **Run directory under the target root**, mirroring `.prowl/handoff/`: sandboxed agents
  read cwd-relative files most reliably; definitions live beside it in
  `<root>/.prowl/workflows/` so a repo can ship its workflows.

## Decisions recorded during design review (2026-08-21)

- **Handoff CLI**: `prowl workflow run prowl.handoff` is the primary invocation. The
  shipped `prowl handoff to|save` stays as a **deprecated alias** (stderr warning per 060's
  deprecation policy; the `prowl.cli.handoff.v2` response shape is kept
  schema-compatible by the `LegacyHandoffAdapter`, with semantic differences documented)
  and is retired afterwards. The `.prowl/handoff/` artifact contract survives inside the
  `handoff.transition` action.
- **Binding default**: built-ins use `bind: ask`. Users switch a workflow to `auto` without
  editing the file: a "Don't ask again for this workflow" toggle in the start sheet and a
  per-workflow toggle in Settings › Workflows store a local override next to the binding
  memory. Direction: V1 edits YAML in an external editor; a GUI editor with file ↔ UI
  two-way sync is the long-term goal (see Open questions for the round-trip constraint).
- **CLI-driven orchestration primitives ship with #699**: `prowl create tab|pane
  --profile <name|uuid> [--prompt -]`, `prowl profiles list`, `prowl agents wait` are part
  of the prerequisite PRs, not a later wave.
- **Settings IA**: Agents becomes a sidebar group with Profiles / Workflows / Command Line
  Tool pages (see Design / UI); the CLI install leaves Advanced.
- **No default wall-clock timeout; state-driven watchdog with grace periods** (see Design
  / Execution model). Detection is heuristic, so every trigger is designed to be harmless
  when wrong: grace before acting, a nudge that only asks the agent to finish with `done`
  when it is truly complete, and attention states that never discard a late delivery.
- **PR order**: C0 → A1 ∥ B1 → A2 ∥ B2 → B3 → C1 → C2 → D1 → D2 → D3 (see Delivery
  slicing); the new Adversarial Review flow validates the engine before the shipped handoff
  is migrated.
- **Review round (2026-08-22)** — accepted corrections: runner as an `AppFeature` child
  fed by the single event subscription + a per-surface multicast observer for CLI waits;
  opaque per-step delivery tokens for `done`; `LegacyHandoffAdapter` with a full parameter
  map instead of a "byte-compatible" claim; binding memory scoped by definition source +
  repository and re-validated; `pick` restricted to the source worktree; `kind: headless`
  moved to V2; output size caps, slug-safe ids, run-directory containment, and the
  privacy wording split into Prowl metadata vs. agent-authored outputs; `until` checked
  before entry and after each iteration.
- **Review round 2 (2026-08-22)** — accepted: typed `ObservedAgentState` observer
  (snapshot / changed / removed / surfaceClosed, per-subscriber buffering, `AGENT_GONE`
  mapping for `agents wait`); the generated completion command is the only spelling in
  built-ins/examples, `--token` in the grammar, shell-safe UUID tokens, tokenized nudges;
  `LegacyHandoffAdapter` admits a bare-shell source when the brief is pre-supplied/skipped
  and uses `failurePolicy: .fail` → `HANDOFF_FAILED`; skipping an output referenced later
  ends the run as `skipped`; binding memory keyed additionally by a role-requirements
  digest; `message` steps advance only after a successful synchronous injection (no
  Prowl-side queue); P2 wording fixes (role `name`/`pane` semantics, `run` source
  grammar, privacy phrasing, `repeat` terminal results).
- **Review round 3 (2026-08-22)** — accepted: one completion-command renderer (token +
  verdict choices, used for hints, nudges, re-deliveries); §3 binding key with a canonical
  role-requirements digest as the single normative definition; per-activation identity
  and tokens for `repeat`; `expect` restricted to `message`/`launch`; source-specific
  `--role` grammar incl. `pick` panes; `LegacyHandoffAdapter` preflight (`BRIEF_REQUIRED`
  / `EMPTY_INPUT` / `INVALID_BRIEF`, legacy failure mapping); rendered-text boundary
  (post-substitution single-line validation, single-line string inputs, `UNSAFE_PATH`);
  `skill:` restricted to the embedded registry; wording cleanups (runtime input queue,
  bare-shell `current`, privacy phrasing, atomic observer registration, slug patterns).
- **Review round 4 (2026-08-22; verified item by item before adopting)** — the renderer
  now emits one complete executable command per verdict value on every transport (no
  placeholders); run-global monotonic activation ordinals make `outputs/<name>.<ordinal>.md`
  and `instructions/<step>.<ordinal>.md` collision-free, with atomic "latest" replacement;
  native actions declare typed input/output schemas and `actions.<step>.<key>` is validated
  like `outputs.*` (known action, declared key, producer dominates consumer); `repeat.max`
  is a positive integer literal or exactly one integer-input template, resolved at start,
  bounded `1…20`; verdict values are unique safe slugs and `until` literals must be
  declared; optional fixes (`UNSAFE_PATH` listed, `tN` in the source grammar, concepts
  table and binding text aligned with the DSL, `notify` fallback without a `current` role,
  legacy parity list includes the preflight cases).
- **Review round 5 (2026-08-22; verified before adopting)** — run-directory specifics in
  the plan now defer to the DSL spec (§§5/8 normative); a run-global *invocation* ordinal
  is minted on entry to every `message`/`launch` execution (artifact naming for
  non-waiting steps too), with *activation* = waiting invocation; `--role r=<binding>` in
  the synopsis; `agents wait` wording aligned with the `ObservedAgentState` observer and
  `AGENT_GONE` payload; a compact V1 action schema table added to the DSL.
- **Review round 6 (2026-08-22; verified before adopting)** — `handoff.checkpoint.briefing`
  is optional (absent = context-only checkpoint, preserving today's `handoff save
  --no-brief`) with a `has_briefing` output, and both `save` variants join the legacy
  parity matrix; message Retry is a new invocation (token revoked and re-minted; guidance
  when an insert succeeded but the submit failed); the plan's token paragraph now
  cross-references the DSL invocation/activation lifecycle.
- **Review round 7 (2026-08-22; verified before adopting)** — absent
  `handoff.transition.briefing` is normatively the context-only *transition* (archive,
  remove stale `current.md`, regenerate context, context-only kickoff, `has_briefing:
  false`) — distinct from the checkpoint rule; `--no-launch` freezes the receiver as a
  typed destination-only binding (token, no profile/pane/plan) that `handoff.transition`
  resolves `to` from, profile lookup happens only when a launch is requested; both cases
  join the parity matrix; Retry revokes/re-mints a token only when the step has `expect`.
- **Review round 8 (2026-08-22; verified before adopting)** — internal-only *seeded
  outputs* give a pre-delivered legacy brief a legal run-store identity (run-global
  ordinal, `outputs/brief.<ordinal>.md`, `seeded` record, no token/pane), preserving the
  invalid-brief-before-any-artifact property; the destination-only binding is
  cross-referenced from the binding model, the `run` response, and `run.json`.
- **Review round 9 (2026-08-22; verified before adopting, mechanism chosen differently)** —
  instead of an adapter-private input overlay, the Skip rule tolerates missing outputs for
  optional action inputs (key absent → `handoff.transition` context-only), which serves
  `--no-brief`, `save --no-brief`, and the GUI "Context Only" skip with one rule; `current`
  role admission depends on whether a message will actually be delivered (pre-skipped and
  seeded-completed steps do not count); seeded outputs are validated against the step's
  `expect`; outputs may be agent- or caller-authored.

## Open questions

- GUI workflow editor (V2): Yams does not preserve comments/formatting on re-serialization;
  two-way sync needs either a comment-preserving writer or a "managed file" policy.
- Exact Swift interface shapes for the split primitive, the launch boundary, and the
  CLI additions of A1/A2, plus the test strategy — final design round.

## Amendments

(append `- Updated 2026-MM-DD: ... — see [00N-topic.md](00N-topic.md)` lines here)
