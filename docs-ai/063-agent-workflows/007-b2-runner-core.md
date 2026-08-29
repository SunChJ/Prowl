# 063.007 — Workflow Runner Core (B2): Plan

## Status

In progress on `feat/workflow-runner-core-b2` (2026-08-29). The decisions below were grilled with
onevcat on 2026-08-29 before code (H2, H4, H5, H6, H8, H10, H11, H12, H7 each settled on the
recommended option); the "Delivered" section is written when the slice lands.

## Context

B1 (#740) made a workflow file parseable, validatable, and listable; #733 (#741) gave the
dispatch store a re-dispatch into an existing pane; #726 T0 (#739) added the version attestation.
B2 is the engine that turns a validated `WorkflowDefinition` into a run: the state machine,
the run directory, the renderers, delivery validation, the exact-signal-first watchdog, the native
actions, and pure binding resolution. It ships no user-facing surface and stays dormant on `main`:
B3 wires it into TCA and the CLI (`prowl workflow run/status/done/cancel`), C1 makes runs visible.

Decisions G1–G6 ([006](006-b1-definitions.md)) and the 2026-08-29 spec amendments are inputs, not
subjects: activation = dispatch record, no `WorkflowRequestRegistry`, `message` injects only into an
idle role, `launch.prompt` may be multi-line, the watchdog consumes exact signals first.

## Decisions

Every row was either a default derivable from the code base (H1, H3, H9, H13) or grilled on 2026-08-29; the
"Alternatives rejected" column records what the grill turned down.

| # | Decision | Alternatives rejected |
| --- | --- | --- |
| H1 | **B2 lives in `supacode/Domain/Workflow/` (app target), tests in `supacodeTests/`.** It depends on app types (`AgentSignal`, `ObservedAgentState`, `AgentProfile`, `HandoffStore`, dispatch records) that never enter `ProwlCLIShared`. Two additions go to Shared: `WorkflowSchema.tokenEnvironmentKey` (`PROWL_WORKFLOW_TOKEN`, read by B3's CLI `done`) and the markdown fence/preamble normalizer that `HandoffStore.validatedBriefing` and the delivery validator share. | Putting the text-level helpers (template renderer, completion command, delivery validation) in Shared so `swift test` covers them: nothing in the CLI consumes them in V1 and Shared carries the `nonisolated` / name-collision tax; revisit if B3 wants a local pre-validation in `done`. |
| H2 | **Reducer-style core.** `WorkflowRunMachine.apply(_ event) -> [WorkflowRunEffect]` is a pure, synchronous transition over a `WorkflowRun` value; every transport concern (idle wait, injection, launch, native action, notify, close, persistence, watchdog arming) is an *effect* B3's `WorkflowRunsFeature` interprets with the terminal boundaries. B2 tests drive the machine directly and, for the composition, through a test harness that interprets effects against fakes (store on a temp directory, fake bridge, `TestClock`). The harness is the executable specification of how B3 must interpret each effect. | A stateful `WorkflowRunner` class in B2 that owns state and calls the boundaries itself (B3 would either wrap it as an `@Observable` store beside TCA or discard it; the plan says the runner is reducer-owned). Async methods on the machine (transitions entangled with I/O; the Retry/Relaunch/Skip/Cancel × phase matrix becomes hard to pin). |
| H3 | **Activation bridge = one protocol, `WorkflowActivationBridge`**, with exactly the dispatch-store operations the effects need: open a message activation (issue + bind to the pane's current epoch, #733's `issueAgentDispatch(boundTo:)`), abandon with a reason, observe a record, complete a record on delivery. The launch activation is opened by the launch boundary itself (S2's issue → attach → launch → bind), so the `.launch` effect carries the token and the environment values and receives the dispatch id back in `.launched`. B2 tests use a fake. | Folding the operations into `TerminalClient` closures now (that is B3's wiring); a second registry (rejected in G1). |
| H4 | **Token check lives in the machine, not in the store.** Each activation holds its token in `WorkflowRun` state; `done` in B3 resolves the caller pane → its pending dispatch id → the run and activation (through `WorkflowRun.activation(forDispatchID:)`) → `machine.deliver(ordinal:token:body:verdict:)`, which answers `STEP_NOT_EXPECTING` / `TOKEN_REQUIRED` / `TOKEN_INVALID` / `OUTPUT_*` / `VERDICT_REQUIRED` itself. `dispatch-complete` against a workflow activation is refused by B3's handler from the same index (`WORKFLOW_DELIVERY_REQUIRED` with the replacement command rendered by B2). The dispatch store (064 code) is untouched. | Storing the token in `AgentDispatchBinding` and checking it in `AgentDispatchStore.complete` (the store would learn workflow semantics; every 064 completion path would grow a branch). |
| H5 | **`run.json` is `WorkflowRunRecord` v1**: top-level `version: 1`; `run` (id, workflow id/name, scope, definition path, status, started/updated/finished), `worktree` (id, name, branch, path), `inputs`, `bindings` (per role: source; launch → profile id/name/agent, pane id/handle once launched; current/pick → pane id/handle, detected agent), `invocations` (ordinal, step, iteration, role, kind, instruction path, activation → dispatch id + state `waiting/delivered/skipped/revoked` + output name/path/verdict), `outputs` (latest per name), `actions` (step → declared keys), `loop` (count), `steps` (entered step records with state). **Delivery tokens are not persisted** (correlation only, useless after restart, and the file then carries nothing a reader could replay); dispatch ids are (needed by `status` / `agents wait --dispatch`). No environment values, extra arguments, home paths, or credentials — the frozen launch *plan* stays in memory with B3, only profile id/name/agent reach the file. Readers tolerate unknown keys; the launch-time `interrupted` scan reads only `version` and `run.status`. | Persisting the token (no consumer); persisting the launch plan (its surface environment carries override values); a schemaless dictionary. |
| H6 | **Watchdog observes per activation**: `observeAgentDispatch(id)` (already epoch-gated by the store: `.needsInput`, `.incomplete` = coalesced `turn-ended`, `.changed(gone)`) for exact evidence and `observeAgentState(surfaceID)` for detector levels, `removed`, `surfaceClosed`, plus a `snapshot(surfaceID:)` re-read at every grace expiry. Two streams and an injected clock per waiting activation, torn down with it. | One bus through `AppFeature`'s single `eventStream` subscription (the 2026-08-22 topology, written before 064-S1 shipped the multicast observer; the spec §10 already names `observeAgentState` / `observeAgentDispatch`). |
| H7 | **Attention and nudge copy** (the only strings agents and users see from B2): nudge `[Prowl] When your work for this step is fully complete, finish with: <commands>`; attention reasons (panel text, C1 renders): *needs input* "The reviewer is waiting for input in its pane" (Focus pane / Cancel), *idle without delivery* "The reviewer has been idle for 3 min without delivering findings — nudged once" (Nudge again / Keep waiting / Skip / Cancel), *blocked* (heuristic) "The reviewer looks blocked (screen) for 30 s" (Focus pane / Cancel), *agent gone* "The reviewer's agent session ended" / "…pane was closed" / "…process is gone" (Relaunch / Skip / Cancel for launch roles; Skip / Cancel otherwise), *injection failed* "The line could not be typed into the author's pane" with the unsubmitted-line hint when the insert succeeded (Retry / Skip / Cancel), *launch failed* (Retry / Skip / Cancel), *rendered text invalid* (Skip / Cancel), *action failed* (Retry / Cancel), *timeout* (`on_timeout: attention`: Nudge / Keep waiting / Skip / Cancel). | Free-form strings composed in C1 (two places to keep in sync). |
| H8 | **Relaunch is offered for `launch` roles only.** It abandons the current activation, mints a new invocation for the *current* step, and re-delivers it as the kickoff prompt of a fresh launch of the frozen profile (message content + workflow protocol block); the role's pane is rebound on `.launched`. A `current` / `pick` role that is gone offers Skip / Cancel (a "Rebind pane" action is V2). | Relaunching a `pick` role by re-running the picker (needs C2's sheet; not a runner concern). |
| H9 | **`agents wait --dispatch <id>` works on activations, so B2 records the dispatch id per activation** in state and `run.json`; the `run`/`status` responses (B3) read it from there. | Exposing only the token (the store is addressed by dispatch id). |
| H10 | **Binding resolution in B2 = the pure resolver**: `WorkflowBindingResolver.resolve(role:remembered:override:context:)` walks remembered → `suggest` exact match → Recommended (053: designated → last launched → first enabled, over the `agents`-filtered set) → `.ask(candidates:)`; every candidate is re-validated (exists, enabled, satisfies `agents`, adapter renders a seeded prompt — probed through `AgentRuntimeAdapterRegistry.makeStartInvocation(.prompt)`, injectable); the memory key is `(scope, workflow id, role, SHA-256 of canonical `{source, kind, agents, suggest}` JSON)`. B3 owns the `@Shared` memory, `--role` parsing, and freezing the plan; C2 owns the sheet. | Reading profiles/settings inside B2 (no `@Shared` in a pure module). |
| H11 | **Skip resolves its consequence immediately.** Skipping an activation (panel, `on_timeout: skip`, `--skip` at start) computes the §5 consequence from the remaining steps: a later template / `until` / required action input → the run ends `skipped(step, dependent)` at once; only optional action inputs continue (key absent). The same query (`WorkflowRun.skipConsequence(for:)`) feeds the panel's confirmation text. | Ending the run lazily when the consumer is reached (a `notify` or `close` between them would still run). |
| H12 | **Native actions run through `WorkflowActionExecuting`**; `WorkflowNativeActionRunner` implements `handoff.transition` / `handoff.checkpoint` over `HandoffCoordinator` (archive-first; absent `briefing` → context-only; transition removes `current.md`) and `git.context` over `HandoffStore.save` (the existing `context.md` generator; outputs `path`, `branch`). `to`'s agent token is the frozen profile binding's agent; an invalid briefing file fails the action (Retry / Cancel). | A separate context generator writing under the run directory (a second generator for the same document). |
| H13 | **The hard `expect.timeout` is scheduled by the watchdog driver** on the same injected clock; it fires `.timeout(policy)` into the machine. | A separate timer effect. |

## Design outline

All new types are `nonisolated` where the app target's MainActor default would otherwise apply,
`Sendable`, and `Equatable` where they enter state.

- `WorkflowRun.swift` — `WorkflowRun` (id, definition, `WorkflowRunContext` {scope, worktree
  facts, inputs, run directory}, `bindings: [String: WorkflowRoleBinding]`, `status:
  WorkflowRunStatus`, `phase: WorkflowRunPhase`, position cursor with loop state, `invocations:
  [WorkflowInvocation]`, `outputs: [String: WorkflowOutputRecord]`, `actionOutputs`,
  `skippedOutputs`, `loopCount`, `stepRecords`), `WorkflowRoleBinding` (`current(pane)`,
  `pick(pane)`, `launch(profile, pane?)`), `WorkflowPaneIdentity` (surface id, tab id, handle,
  display name, agent token), `WorkflowActivation` (ordinal, step, role, token, dispatch id?,
  expect, state), `WorkflowAttention` (reason + `Set<WorkflowAttentionAction>`),
  `WorkflowRunStatus` (`running`, `needsAttention`, `completed`, `cancelled`, `skipped`,
  `maxRoundsReached`, `interrupted`).
- `WorkflowRunMachine.swift` — `WorkflowRunEvent` (`roleIdle`, `injectionSucceeded/Failed`,
  `launched/launchFailed`, `actionCompleted/Failed`, `watchdog(ordinal, verdict)`,
  `timeout`, `user(action)`), `WorkflowRunEffect` (`awaitRoleIdle`, `materializeInstruction`,
  `inject`, `launch`, `runAction`, `notify`, `close`, `abandonActivation`, `completeActivation`,
  `armWatchdog`, `disarmWatchdog`, `persistOutput`, `persist`, `log`, `finished`), `start(...)`,
  `apply(_:)`, `deliver(...) -> Result<WorkflowDeliveryReceipt, WorkflowDeliveryError>`,
  `skipConsequence(for:)`, `activation(forDispatchID:)`.
- `WorkflowTemplateRenderer.swift` — `WorkflowTemplateContext` (typed §6 whitelist) and
  `WorkflowTemplate.render(_:context:)`; `WorkflowTemplateError.missingOutput` is the Skip rule's
  runtime signal.
- `WorkflowLineRenderer.swift` — `WorkflowCompletionCommand` (message form with the env prefix,
  launch protocol block, nudge, instruction-file trailer, `WORKFLOW_DELIVERY_REQUIRED` message),
  typed-line formats with `AgentDispatchPrompt.injectedPrefix`, `WorkflowRenderedText.validate`
  (no line terminators, no C0/C1; `RENDERED_TEXT_INVALID`), the 32 KiB / NUL prompt gate
  (`PROMPT_TOO_LARGE`).
- `WorkflowDeliveryValidator.swift` — format (`markdown` normalized like
  `HandoffStore.validatedBriefing`, `text`, `json`), `sections`, `verdict` (`VERDICT_REQUIRED`,
  undeclared → `OUTPUT_INVALID`), size (`WorkflowDeliveryLimits`: default 1 MiB, hard max 4 MiB →
  `OUTPUT_TOO_LARGE`).
- `WorkflowRunStore.swift` — `<root>/.prowl/workflow-runs/<run-id>/` layout, self-ignoring
  `.gitignore`, `WorkflowRunRecord` (Codable, `version` 1), append-only `log.md`,
  `instructions/<step>.<ordinal>.md`, `outputs/<name>.<ordinal>.md` + atomically replaced
  `outputs/<name>.md`, `skills/<id>/` copied from the bundle, every path from validated slugs and
  the run UUID under `AgentProfileHomeProvisioner.validatePhysicalContainment`, and
  `markInterruptedRuns()` for launch.
- `WorkflowWatchdog.swift` — `WorkflowWatchdogSettings` (`turnGrace` 15 s floor 5 s, `idleGrace`
  3 min, `blockedGrace` 30 s), the pure `WorkflowWatchdogPolicy` (phase machine over observation
  events and deadline expiries; exact mode when a `verified_live` channel covers `turn-ended`,
  heuristic otherwise; one automatic nudge per activation), and the `WorkflowWatchdog` driver that
  merges the two streams, schedules cancellable deadlines on the injected clock, and yields
  `WorkflowWatchdogVerdict`s (`nudge`, `attention(reason)`, `timeout`).
- `WorkflowActivationBridge.swift` — the protocol of H3 and the failure enums the machine maps
  (`roleBusy` → back to `awaitRoleIdle`, `surfaceMissing`, `insertFailed`, `submitFailed`,
  `capacityExceeded`).
- `WorkflowNativeActions.swift` — H12.
- `WorkflowBindingResolver.swift` — H10; `WorkflowBindingMemoryKey` (Codable) with the digest.
- Shared: `WorkflowSchema.tokenEnvironmentKey`; `MarkdownArtifactNormalizer` (fence/preamble
  stripping moved out of `HandoffStore`, which now calls it).

## Test plan (red first)

- Machine: linear run through message → launch → repeat → action → notify → close; `until`
  before entry (satisfied → loop skipped, `loop.count` 0) and after each iteration; `max`
  reached → `maxRoundsReached`; latest-wins outputs across steps with the same name; `until`
  reading the body's final producer; Skip consequences (template / `until` / required input end
  the run, optional input continues with the key absent, `--skip` at start); every attention
  reason with its action set; Retry mints a new ordinal and token; Relaunch re-delivers the
  current step as a launch prompt and rebinds the pane; Cancel abandons with a reason naming run
  and step and keeps outputs; late delivery during attention accepted; delivery after Skip →
  `STEP_NOT_EXPECTING`; wrong / missing token; duplicate delivery; `roleBusy` returns to the
  idle wait; message advances only after `injectionSucceeded`; self-initiated first step.
- Renderers: every §6 variable; `roles.<r>.pane` after launch; single-line boundary rejects
  `\n`, `\r`, U+2028/2029, C0/C1 (tab included) without partial output; completion command with
  and without verdict, joined per value; nudge; launch protocol block; instruction trailer;
  prompt cap and NUL.
- Delivery validation: markdown fence/preamble stripping, missing section, `text`, `json`
  parse failure, empty body, verdict required / undeclared / not declared, 1 MiB default, 4 MiB
  hard max.
- Store: layout and `.gitignore`; versioned + latest outputs (atomic replace); instruction and
  skill materialization; unsafe slugs rejected; symlinked run-directory leaf rejected; escaping
  path rejected; `run.json` round trip without tokens/env; interrupted scan flips only
  non-terminal runs.
- Watchdog (TestClock): exact mode — `needs-input` immediate; `incomplete` → 15 s → re-read
  `working`/`session-start`/`progress` re-arms, idle → nudge → 3 min → attention; `session-end`,
  `surfaceClosed`, dispatch `gone` → attention; `removed` diagnostic only when a channel covers
  `session-end`; heuristic mode — `blocked` 30 s, `idle` 3 min → nudge → 3 min → attention,
  `working` cancels; `turn_grace` floor 5 s; hard timeout; keep-waiting never nudges twice.
- Actions (temp git repo): transition with and without briefing (archive first, `current.md`
  removed, `has_briefing`), checkpoint keeps an earlier `current.md`, `git.context` outputs.
- Binding: digest canonical form (sorted `agents`, absent keys omitted, prompt edits keep the
  key); remembered → suggest → recommended → ask; a disabled / missing / `agents`-violating /
  prompt-less candidate falls through.
- Harness: the §4 example end to end against fakes, and the `prowl.handoff` shape with
  `--skip brief` (context-only through the optional input).

## What B3 verifies live (B2 has no surface)

Idle wait and re-dispatch against real Claude Code / Codex panes; the typed line reaching the
composer as one entry with the token prefix; a real `prowl workflow done -` resolving through
caller ancestry to the activation; `agents wait --dispatch` on an activation id; the launch
protocol block and `PROWL_WORKFLOW_TOKEN` in the child environment only; the watchdog's nudge
and attention timings on hooked and unhooked runtimes; `dispatch-complete` refused with
`WORKFLOW_DELIVERY_REQUIRED`; run directory contents after a full `prowl.adversarial-review`.

## Verification

(filled in when the slice lands)

## Review

(filled in when the slice lands)

## Open items

(filled in when the slice lands)
