# 066 — Agent Island: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-01 | Implemented the Active Agents-backed Agent Island, shared roster UI, display placement settings, navigation reuse, and regression coverage. | [#753](https://github.com/onevcat/Prowl/pull/753), [000-plan.md](000-plan.md) |
| 2026-09-01 | Corrected built-in notch layout to reserve the physical camera cutout instead of treating notch presence as a boolean. | [#753](https://github.com/onevcat/Prowl/pull/753) |
| 2026-09-01 | Replaced the island Working spinner with the Heixiu cat-and-detaching-tail animation. | [002-heixiu-working-animation.md](002-heixiu-working-animation.md) |
| 2026-09-01 | Superseded the anonymous tail ball with real Agent icon projections and cat-like per-Agent status lamps. | [003-agent-icon-tail-projection.md](003-agent-icon-tail-projection.md) |
| 2026-09-01 | Replaced the white icon plates and geometric outline with an AppIcon-derived mint silhouette, dark state nodes, and tail-origin motion. | [004-app-icon-silhouette-and-motion.md](004-app-icon-silhouette-and-motion.md) |
| 2026-09-01 | Removed the decorative cat, restored shared Active Agents icon behavior, and isolated larger fluid status rings to the compact island. | [005-island-owned-agent-rings.md](005-island-owned-agent-rings.md) |
| 2026-09-01 | Restored the original Active Agents panel implementation in full and replaced the single attention card with an island-owned compact Agent collection. | [006-sidebar-restoration-and-attention-collection.md](006-sidebar-restoration-and-attention-collection.md) |
| 2026-09-01 | Removed custom secondary-island transitions and moved compact overflow to a plain trailing-lower counter while retaining three recent-first, Idle-last Agent icons. | [007-elastic-expansion-and-overflow.md](007-elastic-expansion-and-overflow.md) |
| 2026-09-01 | Aligned attention copy with Active Agents, moved repository/worktree context into two trailing lines, and made the secondary roster content-sized with a `360pt` scrolling cap. | [006-sidebar-restoration-and-attention-collection.md](006-sidebar-restoration-and-attention-collection.md) |
| 2026-09-01 | Made Agent Island opt-in and moved its controls into the existing Notifications settings page instead of adding a toolbar action or separate destination. | [000-plan.md](000-plan.md) |
| 2026-09-02 | Isolated Agent Island from terminal rendering and focus by moving ring rotation to Core Animation, preventing the panel from becoming key, and scoping hidden content and event monitors to active island UI. | [008-render-and-focus-isolation.md](008-render-and-focus-isolation.md) |
| 2026-09-02 | Closed nonactivating Escape, island context-action surfacing, attention Workflow badge, carousel resume, and display hot-plug ordering gaps. | [010-nonactivating-interaction-and-display-refresh.md](010-nonactivating-interaction-and-display-refresh.md) |

## Outcome

Agent Island now projects the existing Active Agents roster into a single top-of-screen panel.
It does not add an agent state, acknowledgement flag, or lifecycle signal: Working, Blocked,
Done, and Idle remain interpretations of `ActiveAgentsFeature.entries`.

- The compact island shows the most recently changed Working entry, advances through multiple
  Working entries every four seconds, and pauses while hovered or while the roster is open.
  When no entry is Working, the compact area remains available as a neutral agent-count entry
  point. The trailing area projects only real runtime icons: non-Idle entries sort by recency from
  left to right and Idle entries stay on the right. Overflow keeps three icons visible and uses a
  small unoutlined trailing-lower `+N` counter. Idle receives a static muted outline; Working, Blocked, and
  Done receive state-colored angular-gradient rings with different circulation speeds.
- Blocked and unviewed Done entries produce an automatically visible compact collection below the
  compact island. One entry uses a narrow single column; multiple entries use two columns, with
  three visible rows before scrolling. The left column shows the Agent and shared `Blocked` or
  `Done` label; the right column uses the same repository and branch/tab subtitle as Active Agents.
  Every entry remains visible and independently actionable; Blocked entries precede Done and
  recency breaks ties. A cell disappears only when the
  corresponding Active Agents state changes or the entry leaves the roster.
- Clicking the compact area opens a secondary island without activating Prowl. Its roster uses
  an island-owned list wrapper around the original `ActiveAgentRow`, display resolution, sorting,
  context menu actions, and entry actions. Idle entries appear here alongside the other states.
  The roster appears directly without a custom movement, scale, fade, or spring transition,
  keeping the compact island stationary while the panel adopts the expanded size. Its viewport
  follows measured row content without bottom filler, caps at `360pt`, and scrolls only above the cap.
- Clicking an island entry first surfaces the main Prowl window and then dispatches the existing
  Active Agents selection action, preserving the exact worktree, tab, pane, plain-folder, and
  Canvas focus behavior. **Open Prowl** surfaces the current main window without changing the
  selected entry. Island-originated **Hand Off…** and **Run Workflow** actions also surface Prowl
  before forwarding to their unchanged shared actions. Outside click and Escape only collapse the
  secondary island, including while another application remains active.

## Implementation

- `ActiveAgentsFeature` owns the island's presentation state and injected-clock carousel effect.
  Derived Working and attention projections keep roster and lifecycle semantics in one reducer.
- `ActiveAgentsPanel` keeps its original row layout and behavior. Narrow shared
  `ActiveAgentRowPresentation` and `ActiveAgentRowContextMenu` helpers keep subtitles, Workflow
  badges, and context-menu actions aligned between the sidebar and `AgentIslandRosterContent`,
  while the island continues to own its container and layout.
- `AgentIslandIconCluster` and `AgentIslandAttentionCollection` own all projected icon styling.
  They render only the runtime glyph plus a state ring—never a lower-right badge. The compact
  cluster orders recent non-Idle entries before Idle and moves overflow into a trailing-lower
  plain `+N` label; the attention collection renders every Blocked or unviewed Done entry as its own cell.
  `AgentIslandStateRingView` owns the fluid non-Idle outline as a Core Animation layer, without a
  display-linked SwiftUI timeline or styling changes in other Active Agents surfaces.
- `AgentIslandWindowController` owns one transparent nonactivating `NSPanel`. It anchors the top
  edge while content grows downward, joins all Spaces and fullscreen applications, and responds
  to display changes and main-window movement without participating in normal window cycling. The
  panel cannot become key, and its local/global event monitors exist only while the visible
  secondary roster is expanded.
- `AgentIslandScreenLayout` resolves a fixed CoreGraphics display UUID when connected, otherwise
  temporarily follows Automatic placement without erasing the saved selection. Automatic uses
  the Prowl window's display, then a built-in notched display, the main display, and finally the
  first connected display. On a notched screen it derives the physical cutout from
  `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, aligns the panel to its center, and reserves
  the exact cutout width between equal compact-content wings.
- The Blocked/Done collection passes the current Workflow role badge through the same subtitle
  resolver as Active Agents and the expanded roster.
- The expanded roster keeps its non-key panel and local/global mouse monitors. A low-frequency
  combined-session Escape key-state poll detects only new key-down edges while expanded, avoiding
  a global keyboard event monitor and its permission/focus implications. Screen-parameter handling
  refreshes the display catalog synchronously before recomputing the panel frame.
- Settings → Notifications contains an **Agent Island** section, disabled by default, with
  Automatic or fixed-display placement. Existing settings JSON without the field decodes to off.
- Reduce Motion replaces carousel, icon-replacement, and fluid-ring motion with static presentation
  or opacity transitions. Secondary-island expansion has no custom animation in either mode.

## Verification

- `make check` — passed: swift-format lint, strict SwiftLint, and project checks.
- `make test` — passed: 2,998 app tests plus the 2-test secondary suite, zero failures.
- `make build-app` — passed: Debug build completed with zero errors and zero warnings.
- The 54-test focused Agent Island/App group passes, including Escape edge detection, context-menu
  routing, Prowl-before-action forwarding, Workflow badge projection, carousel resume after roster
  actions, and the continuous title-refresh checks at four and eight seconds.
- Reducer tests cover recent-entry selection, four-second rotation, hover pause/restart,
  Blocked/Done priority, existing Done-to-Idle and Blocked-clear transitions, removal, expansion,
  collapse, and entry selection.
- Navigation tests verify that island selection surfaces Prowl before reusing the existing
  precise focus path; the existing focus coverage continues to exercise worktrees, plain folders,
  Canvas, and closed or minimized main windows.
- Layout and persistence tests cover old JSON defaults, fixed UUID persistence, disconnect
  fallback and reconnect recovery, notched geometry, floating-pill geometry, and negative screen
  coordinates.
- The notch regression fixture uses the connected built-in display's measured geometry:
  `1512×982`, `32pt` safe-area inset, and a `185×32pt` cutout. Seven targeted screen-layout tests
  pass, including exact auxiliary-area derivation and content exclusion.
- The sidebar row layout and behavior remain equivalent to `origin/main`; only the narrow shared
  presentation and context-menu helpers were extracted after `main` added Workflow badges and
  **Run Workflow**. Targeted coverage passes for the original Bagua indicator, island icon
  projection, and attention layout; the latter verifies narrow single-entry presentation,
  two-column multi-entry layout, and scrolling after three rows.
- Isolation coverage verifies that the panel cannot become key, event monitors are limited to a
  visible expanded roster, combined-session Escape detection fires once per key-down edge, the
  compact panel does not retain the `420pt` roster width, and Core Animation rotation stops for
  Idle and Reduce Motion. The PR changes no files under
  `supacode/Infrastructure/Ghostty` or `supacode/Features/Terminal`.
- Manual verification on an external MateView covered the floating pill, secondary roster,
  windowless persistence, **Open Prowl**, and entry-driven restoration and focus. The latest
  compact-only projection was checked with one and two Idle runtime icons plus two captured frames
  of a Working icon: the 21pt icons remained distinct, no decorative cat remained, the static Idle
  rings stayed quiet, and the orange gradient advanced continuously around the Working icon
  without moving its glyph.

## Verification limits

The latest compact visual was checked on the external display before the render-isolation pass.
The Core Animation ring replacement preserves the same geometry, state colors, and durations in
code and passes the layer-lifecycle tests, but it has not received another in-app visual pass.
Built-in notch placement did not change and remains covered by the exact `NSScreen` geometry
fixtures rather than another physical notch run. Stage Manager and cross-Space/fullscreen
transitions were not toggled during the run; the panel's AppKit collection behavior is configured
for those environments, but they remain candidates for release verification.

## Deviations from plan

- No separate navigation helper was introduced in `RepositoriesFeature`: forwarding the island
  action to the existing `entryTapped` action after surfacing Prowl provides a smaller single
  focus path with the same behavior.
- Manual interaction coverage was completed on the external display; the physical-notch
  correction was verified from the built-in display's exact auxiliary-area geometry as described
  above.

## References

- Primary PR: [#753](https://github.com/onevcat/Prowl/pull/753)
- Plan: [000-plan.md](000-plan.md)
- User manual: [Agent Island](../../docs/components/agent-island.md)
