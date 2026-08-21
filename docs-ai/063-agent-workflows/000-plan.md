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
| Role | A participant: `source: current` (the pane the run was started from), `pick` (an existing detected agent pane chosen at start), or `launch` (a new agent Prowl starts). `launch` roles are `interactive` (TUI in a tab/split) or `headless` (one-shot adapter process with captured output). |
| Binding | Role → concrete Agent Profile, resolved at start and frozen into the run. |
| Step | One verb: `message` (say something to a live role), `launch` (start a launch role), `action` (built-in Swift action), `notify`, `close`; plus `repeat` blocks. Each step has a `title` for the status slot and an optional `expect`. |
| Expect | What must happen before the run advances: a named `output` delivered by the role via `prowl workflow done`, optional `sections`/`format` validation, optional `verdict` enum, `timeout`, `on_timeout`. |
| Run | One execution: state snapshot + artifacts under `<root>/.prowl/workflow-runs/<run-id>/`. |

### Execution model: Prowl runs, agents participate

The runner is a TCA feature (`WorkflowRunsFeature`, reducer-owned like the handoff HUD was)
that advances one step at a time through existing terminal boundaries:

- `launch` → the shared profile launch boundary (`launchAgentProfile` extended with
  `AgentStartIntent.prompt`, placement override, anchor surface, background, returning the
  created tab/surface identity — the #651 "shared terminal boundary" done properly).
- `message` → `TerminalClient.sendTextToSurface` into the role's pane, gated by detection
  (`blocked` → not injected, run enters `needsAttention`; `working` → queued, shown).
- `expect` → a `WorkflowRequestRegistry` entry (generalizing `HandoffRequestRegistry`):
  (run, step, role) claimable exactly once by `prowl workflow done` from the role's pane.
- `action` → a registry of native Swift actions (`handoff.transition`, `git.context`).
- `notify`/`close` → the existing bell pipeline and protected close path.

**Data channels.** Inbound to an agent is always *file + short pointer*: long
`instruction` text is materialized to `run.dir/instructions/<step>.md` and one line is
typed (or passed as the kickoff prompt); short `text` is typed verbatim (single line).
Outbound is `prowl workflow done [--verdict v] -` (stdin), resolved to (run, role, step) by
caller-pane identity — no ids in the typed command, so shared YAML carries nothing
machine-specific. `headless` roles are the adapter-stable alternative: output is captured
by Prowl (`.headless` intent, stdout or `--output-last-message`-style files). Transcript
observation (`agents read`) is reserved as a V2 assist, not a V1 channel.

**Data bus.** `<root>/.prowl/workflow-runs/<run-id>/` holds `run.json`, `log.md`,
`instructions/`, `skills/`, `outputs/<name>.md` (versioned per repeat iteration, latest
wins in templates), `captures/`. Distribution is "the next instruction names the path";
Prowl never inlines one agent's output into another agent's input box.

**Binding resolution** (per `launch` role, at start): remembered binding
`(workflow id, role) → profile UUID` in `UserGlobalSettings` → enabled profile matching
`suggest` exactly → 053's Recommended filtered by `agents` → ask. The Start sheet shows a
picker per role with "Create profile from suggestion…" when nothing matches; `bind: auto`
skips the sheet when resolution is unambiguous. `--role r=<name|uuid|auto>` overrides from
the CLI.

**Waiting is state-driven, not wall-clock.** `expect` has no default timeout: a working
agent is never interrupted however long it takes. Instead the runner's watchdog consumes
the existing detection events (`agentEntryChanged` / `agentEntryRemoved`, produced by the
periodic detection schedule) with grace periods, because detection is heuristic and a
wrong guess must be harmless: a role `blocked` for ≥ `blocked_grace` (default 30 s) →
`needsAttention` (Focus pane / Cancel); a role `idle`/`done` for ≥ `idle_grace` (default
3 min) without `done` → Prowl **auto-nudges once** (types `[Prowl] When your work for this
step is fully complete, finish with: prowl workflow done -`, harmless if the agent was in
fact still working — it just queues) and escalates to `needsAttention` (Nudge again / Keep
waiting / Skip / Cancel) only after another `idle_grace`; the role's agent process
disappearing → `needsAttention` (Relaunch role / Skip / Cancel). `needsAttention` is a UI
state, never a deadline: a late `done` is still accepted. Grace values are global settings
(Settings › Workflows); an author may still add an explicit `expect.timeout` with
`on_timeout: attention|skip|cancel` for hard caps.

**Invariants** (carried from 047/053/#651): a pane belongs to at most one run at a time
(`PANE_BUSY`); injection only into panes bound to the run; roles and their plans are frozen
at start; `done` is accepted only from the bound pane unless an explicit `--run/--step`
(manual, logged) or `--force` is given; attention states wait for a person, they never
discard delivered outputs; cancel never closes a pane; extra arguments, environment
values, home paths, and credentials never enter requests, payloads, artifacts, or logs;
the runner performs no git writes.

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
[-|--file] [--verdict v] [--run --step] [--force] | cancel <run> | validate <file> |
schema`; `prowl profiles list` (read-only, for CLI-driven orchestration); prerequisites
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
  `prowl handoff to --brief -` alias starts this run through the runner's internal API with
  the `brief` output pre-delivered from stdin; `--no-brief` pre-marks the step skipped;
  `prowl handoff save` maps to a small `prowl.handoff-checkpoint` built-in.
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
  idle|done|blocked|changed --timeout 1…3600` subscribes to the per-surface
  `ActiveAgentEntry` events (immediate return when already satisfied; `WAIT_TIMEOUT`
  otherwise) and returns `{status, raw_state, waited_ms}` (`prowl.cli.agents.wait.v1`).
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
  runtime-agnostic, validated, correlated by caller pane, and proven by the inline brief.
  `agents read` covers only Claude/Codex and depends on intermittent session attribution;
  it becomes a V2 assist. `headless` roles are the adapter-stable alternative where
  interaction is not needed.
- **File + pointer inbound; `text` for short lines.** Typed text is one line by
  construction (TUIs submit on newline; `ghostty_surface_text` is not bracketed paste).
  Long content is materialized; short messages are typed verbatim so users can see them.
- **Interactive reviewer by default.** Side-by-side visibility of the review happening is
  part of the product's trust model (onevcat, 2026-08-21); headless is an opt-in role kind.
- **Roles reference requirements, never local profile names.** `agents:` (allowed
  runtimes) + `suggest:` (match-or-create) + remembered local bindings keep shared files
  portable while profiles remain the only launch authority (053 boundary intact).
- **`repeat … until <verdict>` in V1, no expression language.** The one loop onevcat's
  real flow needs is "re-review until clean"; termination reads a machine-declared
  `--verdict`, never prose. `max` is mandatory.
- **Step completion is `prowl workflow done`, not `submit <name>`.** Prowl knows which
  step awaits which pane, so the agent names nothing; output names live in YAML
  (`expect.output`).
- **Run directory under the target root**, mirroring `.prowl/handoff/`: sandboxed agents
  read cwd-relative files most reliably; definitions live beside it in
  `<root>/.prowl/workflows/` so a repo can ship its workflows.

## Decisions recorded during design review (2026-08-21)

- **Handoff CLI**: `prowl workflow run prowl.handoff` is the primary invocation. The
  shipped `prowl handoff to|save` stays as a **deprecated alias** (stderr warning per 060's
  deprecation policy, byte-compatible payload during the window) and is retired
  afterwards. The `.prowl/handoff/` artifact contract survives inside the
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

## Open questions

- GUI workflow editor (V2): Yams does not preserve comments/formatting on re-serialization;
  two-way sync needs either a comment-preserving writer or a "managed file" policy.
- Exact Swift interface shapes for the split primitive, the launch boundary, and the
  CLI additions of A1/A2, plus the test strategy — final design round.

## Amendments

(append `- Updated 2026-MM-DD: ... — see [00N-topic.md](00N-topic.md)` lines here)
