# 047.003 — Plan Calibration & Entry-Point Convergence

| | |
| --- | --- |
| **Status** | Implemented (audit items marked open remain open) |
| **Anchor date** | 2026-07-20 |
| **Primary PRs** | #603 |
| **Related** | [047 plan](000-plan.md), [047.002 resume-authored handoff](002-resume-authored-handoff.md), [048 runtime adapters](../048-agent-runtime-adapters/000-plan.md) |

## Context

The 047/048 plans were written quickly across two waves and the branch then sat
while `main` moved (custom-command identifiers, the `qodercli` detector). Before
building a UI entry point on top of handoff, this wave audited the plans against
the implementation and converged what had drifted. `feature/hand-off` was merged
with `main` (2026-07-20) as part of this wave.

## Audit findings

### Corrected in this wave

1. **Duplicated orchestration.** The 047 plan promised the palette would "use the
   same artifact-first sequence as the CLI", but the sequence existed twice:
   `HandoffCommandHandler.handleTo` and the palette effect each hand-rolled
   prepare → save → archive → launch → log, with two different transition log
   formats. Any UI entry point would have become a third copy. Extracted
   `HandoffCoordinator` (`supacode/Domain/Handoff/HandoffCoordinator.swift`):
   preparation, save, transition artifacts, and the single transition-line
   format now live in one nonisolated type; the CLI handler and the palette are
   thin callers, and a toolbar UI becomes the third caller of the same type.
   The palette's log line changed from a bespoke
   `handoff prepared  from=… to=…` line to the shared
   `<from> → <to>  launch=requested  preparation=…  source=command-palette`
   format. `log.md` is a local history file, not a parsed contract, so the
   format is safe to unify.
2. **Fragmented source capture.** `TerminalClient` exposed three selected-pane
   getters (`handoffSessionContext`, `handoffLaunchObservation`,
   `handoffAgentSession`) that repeated the same state/tab/surface resolution in
   the composition root. Collapsed into one `handoffSourceContext` returning a
   `HandoffSourceContext` (session context + launch observation + native
   session). `handoffSessionContextForSurface` stays separate: auto-save
   addresses an explicit surface, not the selection.
3. **Hard-coded palette targets.** The palette listed `claude`/`codex` with
   literal titles. Targets now derive from
   `AgentRuntimeAdapterRegistry.launchableAgents`, and adapters carry the
   user-facing `displayName` ("Claude Code", "Codex"), so a future verified
   adapter appears in every UI entry point without palette edits. Same-agent
   handoff stays listed deliberately — handing codex → codex is a legitimate
   fresh-session restart on the artifact.
4. **Catalog drift.** `main`'s new `qodercli` detector was missing from
   `HandoffAgentSupport.supportedAgents` (caught by
   `supportedAgentsMatchDetectedAgents`). Fixed, including the docs token
   lists. The mirrored list itself is a deliberate boundary, not an oversight:
   `ProwlCLIShared` cannot import the app's `DetectedAgent`, so the CLI keeps a
   string catalog and the app-side guard test enforces parity. 048's "the
   registry is the source of truth" claim applies to *launch/resume
   capability*, not token recognition.

### Deliberately unchanged

- **`--no-launch` still validates the target token** against the detected-agent
  catalog. Accepting arbitrary strings would silence typos
  (`prowl handoff to clade`) for little benefit; unknown-but-real agents can be
  added to the catalog cheaply.
- **`handoff to`'s save log line carries no preparation marker** — the outcome
  belongs to the transition line (047.002 already specified this; the audit
  confirmed the implementation matches).
- **Auto-save stays mechanical.** No preparation on the working→done/blocked
  transition: a 2-minute headless resume per completion would be wildly out of
  proportion for a background refresh.

### Open (next waves)

- **Discoverability.** Handoff is invisible outside `prowl handoff` and two
  palette rows. Resolved 2026-07-20: the status-capsule + staged-HUD direction
  was chosen from three prototyped proposals and planned as
  [049-agents-toolbar-entry](../049-agents-toolbar-entry/000-plan.md), which
  consumes `HandoffCoordinator`, `TerminalClient.handoffSourceContext`, and
  `AgentRuntimeAdapterRegistry.launchableAgents` directly.
- **Cancellation.** A palette-initiated preparation can occupy up to the
  2-minute resume timeout with only an in-progress toast; there is no cancel
  affordance. The CLI path inherits Ctrl-C. Addressed by 049's execution step
  (Skip and Cancel during the briefing stage); until that lands, the toast-only
  behavior stands.
- **Retention.** `archive/` and `sessions/` grow without bound: every save adds
  a session excerpt, every transition adds an archive, every preparation adds a
  backup. Acceptable for a local, self-ignored directory in the short term;
  revisit with a simple keep-last-N policy once real usage shows the growth
  rate.

## Verification

- `make build-app` — zero warnings.
- Focused suites: `HandoffCommandHandlerTests`, `HandoffStoreTests`,
  `AppFeatureHandoffTests`, `AgentRuntimeAdapterTests`,
  `CommandPaletteFeatureTests` — 133 passed after the convergence.
- Full `make test` and CLI smoke/integration on the merged branch.
