# 063.008 — Workflow Runner Wiring (B3): Plan

## Status

Implemented on `feat/workflow-runner-wiring-b3` (2026-08-29/30), after B2 merged as
[#743](https://github.com/onevcat/Prowl/pull/743); PR
[#744](https://github.com/onevcat/Prowl/pull/744). B3 is the R2a slice that powers the
engine for CLI callers. C1 owns workflow presentation and user attention controls; C2 owns the
start sheet and interactive binding picker.

## Confirmed inputs

- B1 (#740) owns workflow discovery, parsing, validation, and the local `validate` / `schema`
  commands. #733 (#741) owns re-dispatch into an existing idle pane. B2 (#743) owns the pure
  machine, store, renderer, watchdog, native actions, and binding resolver.
- The normative CLI protocol is [dsl-spec §9](dsl-spec.md#9-cli-participant-protocol). B3 must
  not reopen B2 decisions H1–H14.
- B2's `WorkflowRunHarness` is the interpreter reference. In particular, delivery is
  validate → persist output → `.outputPersisted` → complete dispatch / advance; a CLI `done`
  response must not report success before persistence.

## Scope

1. Add a reducer-owned `WorkflowRunsFeature` below `AppFeature`. It holds active in-memory runs
   and interprets every `WorkflowRunEffect` against the terminal, dispatch, launch, store,
   native-action, and watchdog boundaries. `WorkflowRun` remains the persisted state; the feature
   reconstructs the pure machine for each transition with injected date/UUID values rather than
   introducing a stateful runner object.
2. Implement the `WorkflowActivationBridge` over `WorktreeTerminalManager`, and wire:
   - message activation issue/bind → committed text → submit, with issuance rollback on failure;
   - prompted profile launch with workflow-only child environment values and the launch dispatch;
   - per-activation `WorkflowWatchdog` streams (`observeAgentDispatch` and
     `observeAgentState`);
   - output persistence, logging, native actions, close/notify, and terminal-run cleanup.
3. Extend the workflow CLI across all four governed layers: parser/input envelope, app handler,
   versioned payload/output renderer plus executable schema, contracts/manual/skill. Add
   `run`, `status`, `done`, and `cancel` while preserving B1's `list`, `validate`, and `schema`.
4. Resolve a run request from the discovered effective definition and freeze bindings. CLI
   binding resolution uses explicit `--role` overrides, remembered bindings, suggestion, and
   Recommended. A `pick` role without an explicit pane, or a launch role whose resolver reaches
   `.ask`, fails before any side effect; C2 owns the picker. Persist successful launch bindings
   in `@Shared` memory keyed by B2's requirements digest.
5. At app start, scan each known worktree root through `WorkflowRunStore.markInterruptedRuns`.
   V1 does not resume runs; `status <run-id>` can still read the materialized record after a
   restart.
6. Update the 063/release ledgers: #743 is merged, B3 is in progress, and this record is the B3
   plan.

## Boundary decisions

| # | Decision | Reason |
| --- | --- | --- |
| W1 | CLI commands enter the reducer through a request/response rendezvous that owns continuations only, never runner state. `run` replies after preflight, layout, and the initial record persist; `done` replies when its activation leaves `persisting` — delivered/provisional succeeds, persist-failed/revoked/terminal fails — not merely when an `.outputPersisted` event arrives. | The reducer remains the single owner of active runs; a socket handler must nevertheless await `done` persistence before replying. Cancel and store-failure can race a queued output-persist event, whose machine guard intentionally ignores terminal transitions; resolving only on that event would leak a CLI continuation. |
| W2 | B3's preflight means workflow discovery/validity/enabled state, source/worktree resolution, binding legality, pane ownership, and run-directory setup. It does **not** add CLI installation or socket-health UI. | A reachable socket is already a prerequisite of any CLI command; the observable installation/socket status belongs to D1. This resolves the ambiguous “CLI preflight” wording in the slice table. |
| W3 | `workflow done` identifies an activation from the caller pane's pending dispatch first, then checks the machine token. Explicit `--run --step` is the documented manual path; mismatched caller and explicit target is `ROLE_MISMATCH` unless `--force`. `agents dispatch-complete` is intercepted before the normal handler can complete a workflow activation. | Preserves the B1/B2 trust boundary: tokens correlate but do not authenticate. |
| W4 | A non-strict delivery with validation issues persists and becomes `needsAttention`; B3 reports `delivery.state = provisional`, warnings, and the attention vocabulary through `status`, but does not silently accept it. | H14 requires a user decision. C1 supplies Accept / Ask again / Skip / Retry / Relaunch controls; B3 intentionally has only `status` and `cancel` as public lifecycle controls. Before C1, a provisional delivery (and every other attention state) is cancel-only; it cannot be re-delivered because the activation is no longer waiting. R2a is not released with B3 but without C1. |
| W5 | `status` reads an active run from reducer state when available and otherwise reads a v1 record from its indexed worktree root. No run is reconstructed from disk. | Status and `agents wait --dispatch` remain useful after an app restart without accidentally implementing V2 resume. |
| W6 | CLI launch roles use only frozen profile launch plans. `PROWL_WORKFLOW_TOKEN`, `PROWL_WORKFLOW_RUN`, and `PROWL_WORKFLOW_ROLE` are child-only surface environment values, not `run.json` or response data. | Retains B2's privacy rule and prevents a workflow token from leaking to unrelated processes or persisted metadata. |

## Tests and verification

Follow test-first development for the deterministic routing and contract layers. Add reducer/handler
coverage for source resolution, every binding source and override, one-run-per-pane rejection,
`done` attribution/token/force mismatch, two-phase persistence (including Cancel or persistence
failure while a `done` rendezvous waits), dispatch-complete interception, late launch cleanup,
watchdog lifecycle, restart interruption, and structured payload/schema validation. Keep B2's pure suites unchanged except for seams required by real wiring.

Run the CLI unit, smoke, and socket integration targets as required for CLI work; run `make check`
and `make build-app`. Then use an isolated Debug app and matching CLI to drive a real workflow:

- message into an idle existing Claude Code or Codex pane, then a second #733 re-dispatch;
- launch with the protocol block and workflow token visible only to the child;
- `done -` resolved by caller ancestry and followed by `agents wait --dispatch`;
- refused `agents dispatch-complete` with `WORKFLOW_DELIVERY_REQUIRED`;
- watchdog nudge/attention behavior on both hooked and unhooked runtimes;
- a deliberately provisional delivery: verify `done` reports `provisional`, `status` exposes
  its attention, and document that C1 is required to resolve it rather than treating it as a
  happy-path completion;
- output/run-directory inspection and restart interruption.

## Delivered

Everything B3 adds sits between B2's pure domain and the app's boundaries; B2's suites are
unchanged except for one seam.

- `WorkflowRunsFeature` (`supacode/Features/Workflow/Reducer/`) — the reducer-owned run
  table (`sessions`, terminal runs included so `status` keeps answering), `started` /
  `event` / `deliver` / `userAction` / `markInterruptedRuns`. Effects are performed in the
  machine's order through one FIFO per run (`WorkflowEffectQueue`, enqueued synchronously while
  reducing, drained by a single long-lived executor effect per run), so an instruction file exists
  before the pointer line that names it is typed and `run.json` writes never overtake each other;
  idle waits and watchdogs are separate cancellable effects (`cancelInFlight` per ordinal, a
  run-wide id torn down on `.finished`). A materialize failure stops the rest of its batch and
  raises the injection / launch attention. Late (`run` ended) and stale (machine no longer
  expects it) `.launched` events abandon their dispatch record and close the pane. A successful
  launch remembers its profile under B2's digest key (`UserGlobalSettings.workflowBindings`).
- The `done` rendezvous (`WorkflowCLIRendezvous`, `WorkflowCLIResponderClient`): the reducer
  keeps `pendingDeliveries[requestID]` and answers when the addressed activation leaves
  `persisting` — `delivered` / `provisional` succeed, `persist_failed` answers
  `WORKFLOW_FAILED`, a revoked / skipped activation or an ended run answers
  `STEP_NOT_EXPECTING`; a client that disconnects gets `REQUEST_CANCELLED` and the run
  continues. An answer that arrives before the handler awaits is buffered on the slot.
- Admission (`WorkflowRunAdmission`): effective definition (id, then unique name;
  `WORKFLOW_NOT_FOUND` / `WORKFLOW_INVALID` with the validate payload / `WORKFLOW_DISABLED`),
  source rules (W2), bindings in role order (`current`: pane, `PANE_BUSY`, `DISPATCH_PENDING`
  when the pane still holds a pending record — found live: a launched author that never ran
  `dispatch-complete` made the self-initiated activation fail `roleBusy` and the run loop into
  the idle wait —, `AGENT_NOT_FOUND` only when a message to it survives the skips; `pick`:
  explicit `pN` / UUID in the source worktree, same pending-record rule; `launch`: override → remembered → suggestion → Recommended through B2's resolver,
  `.ask` → `PROFILE_NOT_FOUND`, a rejected override or memory is logged into the run and falls
  through), inputs / skips through `WorkflowRunMachine.start`, the frozen launch plan
  (`AgentProfileLaunchPlanner.plan` with a placeholder prompt), layout + initial `run.json`
  before the reply.
- The coordinator (`WorkflowRuntimeCoordinator`): `run` / `status` (W5: live session, else a
  `run.json` from any known worktree root, else `RUN_NOT_FOUND`) / `done` (W3: caller pane's
  pending dispatch → activation; explicit `--run --step` manual; disagreement `ROLE_MISMATCH`
  unless `--force`) / `cancel`. `agents dispatch-complete` is intercepted before the store
  through `AgentDispatchCompleteCommandHandler.intercept` → `WORKFLOW_DELIVERY_REQUIRED`.
- Live boundaries (`WorkflowRuntimeComposition`): `waitForRole` = the #733 evidence rules
  (`AgentConditionEvidence.idleVerdict`, shared with `agents dispatch`) without the 5 s cap —
  exact idle at once, a detector-only idle after 2 s of stability, `working` keeps waiting,
  an exact `needs-input` or 30 s of heuristic `blocked` ends the wait as blocked, 10 s without
  a detected agent as `noAgent`, a closed surface as `gone`, a foreign pending dispatch record
  as `dispatchPending` (the machine seam `.roleUnavailable` maps these to the injection-failed
  attentions, so a pane nobody completes never spins the run between `roleIdle` and
  `roleBusy`); `launch` = issue the
  dispatch → A2 prepare with the placeholder prompt → `attachingWorkflow` (the rendered kickoff
  prompt replaces the placeholder, `PROWL_WORKFLOW_TOKEN` / `_RUN` / `_ROLE` ride
  `PROWL_LAUNCH_WORKFLOW_<n>` carriers the `env` line unsets for the child, exactly like
  `PROWL_DISPATCH_ID`) → launch → bind → focus unless `background`; every later failure cancels
  the issuance and closes the pane. `notify` logs and, when system notifications are enabled,
  posts a banner titled `Workflow · <worktree>`.
- CLI (`prowl workflow run/status/done/cancel`), payload `prowl.cli.workflow.v1` actions
  `run` / `status` / `cancel` (run object) and `done` (`run` + `delivery`), executable schema,
  text renderers, `docs/components/cli.md`, the contract page, and the `prowl-cli` skill
  recipe. `done` reads its body client-side (stdin or `--file`, 4 MiB cap).

## Verification

- Red first for the routing and contract layers: the reducer suite (`WorkflowRunsFeatureTests`:
  ordered execution with the instruction file on disk before the pointer is typed, the `done`
  rendezvous through delivered / provisional / persist-failed / cancelled-while-persisting, late
  and stale launches, the idle-wait outcomes, the restart scan), `WorkflowRunAdmissionTests`
  (definition selection, source rules, every binding source and override, one run per pane, the
  pending-dispatch refusal, start-time validation), `WorkflowRuntimeCoordinatorTests` (`done`
  attribution incl. `ROLE_MISMATCH` / `--force`, `status` live / record / who-am-I, `cancel`),
  `WorkflowCLIRendezvousTests` (buffered early answers, cancellation), the launch-plan carrier
  test, the dispatch-complete interception test, the `.roleUnavailable` machine tests; CLI parser,
  schema (`WorkflowSchemaTests` for every action + Codable round trip), and the mock-socket
  `run` / `done` round trip. `make check`, `make build-cli`, `make test-cli-unit` (233),
  `make test-cli-smoke`, `make test-cli-integration` (110), `make build-app` (0 warnings in the
  changed files), the workflow app suites (121), and `make test`.
- Live, in an isolated Debug instance (`CFFIXED_USER_HOME` scratch home, `PROWL_CLI_SOCKET=
  /tmp/prowl-b3.sock`, `Claude Code` / `Codex` profiles whose `PATH` override puts the bundled
  debug CLI first, a scratch Git repository with `b3-review` and `b3-idle` under
  `.prowl/workflows/`):
  - `b3-review` started from a launched Claude Code pane (`prowl workflow run b3-review --json`
    typed by the agent itself): the response carried `self_initiated.line` with the instruction
    path and the token-bearing completion command, nothing was typed into the caller; the brief
    was delivered with `done -` resolved by caller ancestry (`delivered`); the reviewer profile
    launched in a split with the protocol block in its prompt and — checked from inside the
    child with a masked `env` — only `PROWL_WORKFLOW_TOKEN` / `_RUN` / `_ROLE` in its
    environment (no `PROWL_DISPATCH_*` / `PROWL_LAUNCH_*`); `agents wait --dispatch` on the
    activation's dispatch id returned the succeeded receipt "Delivered output 'findings' …
    with verdict 'issues'"; round 1 messaged the idle author and then the idle reviewer through
    #733 re-dispatch (log: "waiting for role … to be idle" → delivered), `until` exited on
    `clean`, `notify` fired, `close` removed the reviewer pane; `run.json` and `log.md` carry
    dispatch ids and paths but no token.
  - `agents dispatch-complete` from the author while it owed the `fix` delivery was refused
    with `WORKFLOW_DELIVERY_REQUIRED` and the replacement `done` command.
  - A second run delivered a brief without `## Claims`: `done --json` answered
    `delivery.state: provisional` with `missing_sections`, `status` showed `needs_attention` /
    `delivery_issues` with the H14 actions, and `cancel` ended it (activation `revoked`,
    `outputs/brief.md` kept on disk, `outputs` in the record empty). B3 offers no accept /
    ask-again control; that is C1 (decision W4).
  - Found and fixed live: a launched author that never ran `dispatch-complete` still held its
    launch record, so the self-initiated activation failed `roleBusy`, the machine fell back to
    the idle wait, and the run ended in an injection attention while `status` still advertised a
    `waiting` activation `done` could not address. Admission now refuses such panes with
    `DISPATCH_PENDING`, the idle wait ends as `dispatchPending` attention instead of spinning,
    and `status` reports only the activation `done` can address (`WorkflowRun.currentActivation`).
  - `b3-idle` (no `current` role, started from a worktree target) launched its worker, which
    answered "OK" within three seconds; the exact `turn-ended` reached the dispatch record
    (`agents wait --dispatch` → `DISPATCH_INCOMPLETE`) but no nudge followed. Cause, in B2's
    policy: a `turn_grace` expiry that had seen "activity" cleared the flag and scheduled
    nothing, and the detector's first `working` for a freshly launched agent arrives *after*
    the hook's `turn-ended`, so the watchdog went silent for good. Fixed in the policy: an
    expiry that sees activity re-arms the same grace (`turn_grace` / `idle_grace`) instead of
    waiting for an event that may never come; the B2 tests that pinned the silent `[]` now pin
    the re-arm, plus a regression test for the late first detection. Re-verified live after the
    fix: the worker answered "OK" within seconds of its launch, the nudge (`[Prowl] When your
    work for this step is fully complete, finish with: PROWL_WORKFLOW_TOKEN=… prowl workflow
    done -`) was typed 41 s after the run started, the worker answered "OK" again, and 3 min
    later the run entered `needs_attention` / `idle_without_delivery` with the H7 copy
    ("… has been idle without delivering report; Prowl nudged it once"). The heuristic
    (unhooked) watchdog path was not exercised live; B2's policy tests cover it.
  - Restart: the isolated app was killed while `b3-idle` was `running`; after relaunch
    `status <run-id>` answered from `run.json` (`source: record`, `interrupted`, no activation)
    and `log.md` gained "Run marked interrupted at app launch (no resume in V1)".

## Non-goals

No status-center UI, run panel, notifications, start sheet, workflow picker, built-in definition,
workflow authoring skill, Settings page, CLI-install/socket-health status, handoff migration, or
V2 resume/fan-out/observe mode. Those remain C1, C2, D1–D3, and V2.
