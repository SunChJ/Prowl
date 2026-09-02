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

## Outcome & current state (as of 2026-09-02)

Agent Island projects the existing Active Agents roster into one top-of-screen panel. It adds no
agent state, acknowledgement flag, or lifecycle signal.

- **Compact bar** — shows the most recently changed Working entry, rotates through multiple
  Working entries every four seconds, and pauses while hovered or expanded. With no Working
  entry it shows a neutral agent count. The trailing cluster projects up to three runtime icons
  (recent non-Idle first, Idle last) plus a plain `+N`. Idle rings are static; Working, Blocked,
  and Done rings rotate in state colors and stop under Reduce Motion.
- **Attention collection** — every Blocked or unviewed Done entry is its own cell below the bar,
  Blocked before Done, then by recency; one column for a single entry, two otherwise, three rows
  before scrolling. Cells clear only when the underlying Active Agents state changes.
- **Roster** — clicking the bar opens the full list without activating Prowl. Rows reuse
  `ActiveAgentRow` with the shared subtitle resolver and context menu. Clicking a row, a cell, or
  Hand Off / Run Workflow surfaces the main window first and then dispatches the unchanged sidebar
  action. Open Prowl only surfaces the window. Outside click or Escape collapses the roster.
- **Placement** — notched screens merge the bar with the cutout at the physical top edge; other
  screens get a floating pill under the menu bar. Automatic follows the Prowl window's display,
  then a notched built-in display, then the main display. A pinned display is stored by CG UUID
  and falls back to Automatic while disconnected.

Key files:

- `supacode/Features/ActiveAgents/Reducer/ActiveAgentsFeature.swift` — island state, carousel
  effect, `islandWorkingEntries` / `islandAttentionEntries`.
- `supacode/Features/App/Reducer/AppFeature.swift` — surface-then-forward for island actions;
  settings mirror.
- `supacode/Features/ActiveAgents/BusinessLogic/AgentIslandWindowController.swift` — panel,
  observers, expanded-only event monitors and Escape poll.
- `supacode/Features/ActiveAgents/Models/AgentIslandScreen.swift` — `AgentIslandScreenLayout`,
  `AgentIslandNotchLayout`, `AgentIslandDisplayCatalog`.
- `supacode/Features/ActiveAgents/Views/AgentIslandView.swift`, `AgentIslandIconCluster.swift`,
  `AgentIslandAttentionCollection.swift`, `AgentIslandRosterContent.swift` — island-owned UI.
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
  `AppFeatureSettingsChangedTests`) pass — 214 tests. New regressions: hover → remove last entry
  → two Working entries → tick at four seconds; picker selection by UUID with renamed,
  disconnected, and unknown displays.
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
- While Prowl is frontmost, the first keystroke after expanding the roster collapses it; Escape
  is consumed by the island, any other key passes through. In another application only the
  key-state poll runs, so Escape collapses the roster and still reaches that application. The
  asymmetry is a known limitation, not a planned change (2026-09-02).
- `AgentIslandWindowController.start()` creates the panel and observers at launch regardless of
  the setting; starting it only when enabled would tighten the opt-in boundary.
- `AgentIslandNotchLayout.rootWidth` has no callers.
