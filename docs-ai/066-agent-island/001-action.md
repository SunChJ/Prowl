# 066 — Agent Island: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-01 | Initial implementation: reducer presentation state and carousel effect, nonactivating panel controller, screen resolution and settings, docs. | #753 |
| 2026-09-01 | Built-in display validation: notch treated as a measured cutout from the auxiliary menu-bar areas instead of a boolean; compact content uses equal wings around it. | #753 |
| 2026-09-01 | Three visual iterations of a "Heixiu" cat identity (tail-ball Working loop, agent-icon tail projection, AppIcon silhouette) were built and then removed; the compact projection settled on runtime icons with state rings. | #753 |
| 2026-09-01 | Sidebar row/panel files restored to their pre-island state; the attention surface changed from one card plus `+N` to a per-entry collection; roster content-sized with a 360pt cap; custom expansion transitions dropped; feature made opt-in under Settings › Notifications. | #753 |
| 2026-09-02 | Render and focus isolation: ring rotation moved to Core Animation, panel made non-key, event monitors scoped to an expanded roster, compact footprint no longer keeps the 420pt roster width. | #753 |
| 2026-09-02 | Review round 1: carousel survives per-second title refreshes; `main` merged; `ActiveAgentRowPresentation` and `ActiveAgentRowContextMenu` extracted so the island roster shows Workflow badges and Run Workflow. | #753 |
| 2026-09-02 | Review round 2: Escape collapses the roster while another app is active via a key-state poll; island Hand Off / Run Workflow surface Prowl first; Workflow badge in attention cells; synchronous catalog refresh on screen changes; carousel restarts after roster actions. | #753 |
| 2026-09-02 | Fork-owned continuation: `isIslandHovered` reset when the roster empties (review round 3 blocker); unrelated 100-column reflow reverted; display picker matched by UUID; compact bar height aligned to the cutout instead of overhanging it by 8pt (12pt corners, 20pt icons); island content pinned to the top of the hosting view so panel resizes no longer make the icon cluster spring back into place, and the floating pill's carousel identity no longer tears the cluster down; working-note amendments folded into the plan. | #756 |
| 2026-09-03 | Structure and polish: island actions folded into `island(Action)`; panel created only while enabled; display catalog moved to `BusinessLogic/`; island navigation tests in their own file; clipped shadows removed and the roster matched to the bar width; the notched leading wing shows per-state counts instead of a name carousel. | #756 |
| 2026-09-03 | Floating pill switched to the same per-state counts; the name carousel and its reducer state, clock effect, hover tracking, and tests removed. Island roster rows show "pane title · branch". | #756 |
| 2026-09-03 | Contextual exposure formalized as a product rule: each control, hint, and callout must have a relevant, actionable state instead of exposing the island's full capability set at once. | #758 |

## Outcome & current state (as of 2026-09-02)

Agent Island projects the existing Active Agents roster into one top-of-screen panel. It adds no
agent state, acknowledgement flag, or lifecycle signal.

- **Compact bar** — the leading area shows per-state counts (blocked, done, working, idle; empty
  states omitted) as state-colored symbols, compact in the notch wing and one size up in the
  floating pill. The trailing cluster projects up to three runtime icons
  (recent non-Idle first, Idle last) plus a plain `+N`. Idle rings are static; Working, Blocked,
  and Done rings rotate in state colors and stop under Reduce Motion.
- **Attention collection** — every Blocked or unviewed Done entry is its own cell below the bar,
  Blocked before Done, then by recency; one column for a single entry, two otherwise, three rows
  before scrolling. Cells clear only when the underlying Active Agents state changes.
- **Roster** — clicking the bar opens the full list without activating Prowl. Rows reuse
  `ActiveAgentRow` with a "pane title · branch" subtitle (a live Workflow badge still takes the
  line) and the shared context menu. Clicking a row, a cell, or
  Hand Off / Run Workflow surfaces the main window first and then dispatches the unchanged sidebar
  action. Open Prowl only surfaces the window. Outside click or Escape collapses the roster.
- **Placement** — notched screens merge the bar with the cutout at the physical top edge; other
  screens get a floating pill under the menu bar. Automatic follows the Prowl window's display,
  then a notched built-in display, then the main display. A pinned display is stored by CG UUID
  and falls back to Automatic while disconnected.

Key files:

- `supacode/Features/ActiveAgents/Reducer/ActiveAgentsFeature.swift` — island state,
  `island(Action)` forwarding, `islandAttentionEntries`.
- `supacode/Features/App/Reducer/AppFeature.swift` — surface-then-forward for island actions;
  settings mirror.
- `supacode/Features/ActiveAgents/BusinessLogic/AgentIslandWindowController.swift` — panel
  lifecycle bound to the setting, observers, expanded-only event monitors and Escape poll.
- `supacode/Features/ActiveAgents/BusinessLogic/AgentIslandDisplayCatalog.swift` — connected
  screens keyed by display UUID.
- `supacode/Features/ActiveAgents/Models/AgentIslandScreen.swift` — `AgentIslandScreenLayout`,
  `AgentIslandNotchLayout`.
- `supacode/Features/ActiveAgents/Views/AgentIslandView.swift`, `AgentIslandStateSummary.swift`,
  `AgentIslandIconCluster.swift`, `AgentIslandAttentionCollection.swift`,
  `AgentIslandRosterContent.swift` — island-owned UI.
- `supacode/Features/ActiveAgents/Views/ActiveAgentRowSupport.swift` — presentation and context
  menu shared with `ActiveAgentsPanel.swift`.
- `supacode/Features/Settings/Models/AgentIslandDisplayPreference.swift`,
  `supacode/Features/Settings/Views/AgentIslandSettingsSection.swift` — preference model and the
  Notifications section; `GlobalSettings.swift` carries the two fields with legacy defaults.
- `supacode/App/supacodeApp.swift` — controller start/stop in the app delegate.

## Verification

- #753 head (`c4606b06`): CI `test` workflow green; the author reported `make check`,
  `make test`, and `make build-app` passing.
- #756 (this continuation): `make check` passes; the affected suites
  (`ActiveAgentsFeatureTests`, `AgentIslandScreenTests`, `SettingsFeatureTests`,
  `SettingsFilePersistenceTests`, `BaguaWorkingIndicatorTests`, `AppFeatureQuitTests`,
  `AppFeatureSettingsChangedTests`, `AppFeatureAgentIslandTests`, `AgentIslandIsolationTests`,
  `AgentIslandStateSummaryTests`, `AgentIslandIconClusterTests`) pass — 152 tests on the latest
  head. New regressions cover picker selection by UUID, the `island(Action)` forwarding rule,
  panel lifecycle following the setting, state-count ordering, and the combined roster subtitle.
- Manual: the author verified the floating pill, roster, Open Prowl, and entry focus on an
  external display; the built-in notch geometry was captured from a 14-inch display
  (1512×982, 32pt inset, 185×32pt cutout) and is covered by fixtures only.

## Deviations from plan

- No dedicated navigation helper in `RepositoriesFeature`: forwarding to `entryTapped` after
  surfacing Prowl gives the same behavior through one path.
- The planned "one extracted list-content view" shared with the sidebar became a narrower
  extraction (presentation + context menu) plus an island-owned roster wrapper, so the sidebar
  row and panel files stay byte-identical to their pre-island state.
- Escape uses a key-state poll instead of a global keyboard monitor to avoid the
  Accessibility/Input Monitoring prompt.

## Open questions

- A physical-notch, Stage Manager, fullscreen/Spaces, and display hot-plug pass has not been run
  on this branch; the panel's collection behavior is configured for them but unverified.
- The notched bar's wings cover about 120pt of the menu bar band on each side of the cutout and
  intercept clicks there while agents are running (raised by the 2026-09-03 adversarial review).
  Documented as a limitation; narrowing the wings or offering a floating placement on notched
  displays is a product decision still open.
- While Prowl is frontmost, the first keystroke after expanding the roster collapses it; Escape
  is consumed by the island, any other key passes through. In another application only the
  key-state poll runs, so Escape collapses the roster and still reaches that application. The
  asymmetry is a known limitation, not a planned change (2026-09-02).
