# 066 — Agent Island: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-01 | Implemented the Active Agents-backed Agent Island, shared roster UI, display placement settings, navigation reuse, and regression coverage. | TBD, [000-plan.md](000-plan.md) |

## Outcome

Agent Island now projects the existing Active Agents roster into a single top-of-screen panel.
It does not add an agent state, acknowledgement flag, or lifecycle signal: Working, Blocked,
Done, and Idle remain interpretations of `ActiveAgentsFeature.entries`.

- The compact island shows the most recently changed Working entry, advances through multiple
  Working entries every four seconds, and pauses while hovered or while the roster is open.
  When no entry is Working, the compact area remains available as a neutral agent-count entry
  point.
- Blocked and unviewed Done entries produce an automatically visible callout below the compact
  island. Blocked wins over Done, recency breaks ties, and `+N` represents additional attention
  entries. The callout disappears only when the corresponding Active Agents state changes or
  the entry leaves the roster.
- Clicking the compact area opens a secondary island without activating Prowl. Its roster uses
  the same `ActiveAgentsListContent`, row display resolver, status pills, sorting, context menu,
  and entry actions as the sidebar panel. Idle entries appear here alongside the other states.
- Clicking an island entry first surfaces the main Prowl window and then dispatches the existing
  Active Agents selection action, preserving the exact worktree, tab, pane, plain-folder, and
  Canvas focus behavior. **Open Prowl** surfaces the current main window without changing the
  selected entry. Outside click and Escape only collapse the secondary island.

## Implementation

- `ActiveAgentsFeature` owns the island's presentation state and injected-clock carousel effect.
  Derived Working and attention projections keep roster and lifecycle semantics in one reducer.
- `ActiveAgentsListContent` and `ActiveAgentRowDisplayResolver` are shared by the sidebar panel
  and Agent Island, removing the previous duplicated row implementations.
- `AgentIslandWindowController` owns one transparent nonactivating `NSPanel`. It anchors the top
  edge while content grows downward, joins all Spaces and fullscreen applications, and responds
  to display changes and main-window movement without participating in normal window cycling.
- `AgentIslandScreenLayout` resolves a fixed CoreGraphics display UUID when connected, otherwise
  temporarily follows Automatic placement without erasing the saved selection. Automatic uses
  the Prowl window's display, then a built-in notched display, the main display, and finally the
  first connected display.
- Settings adds **Agents → Agent Island**, enabled by default, with Automatic or fixed-display
  placement. Existing settings JSON decodes to the new defaults.
- Reduce Motion replaces the default spring and scrolling transitions with opacity transitions.

## Verification

- `make check` — passed: swift-format lint, strict SwiftLint, and project checks.
- `make test` — passed: 2,936 app tests plus the 2-test secondary suite, zero failures.
- `make build-app` — passed: Debug build completed with zero errors and zero warnings.
- Reducer tests cover recent-entry selection, four-second rotation, hover pause/restart,
  Blocked/Done priority, existing Done-to-Idle and Blocked-clear transitions, removal, expansion,
  collapse, and entry selection.
- Navigation tests verify that island selection surfaces Prowl before reusing the existing
  precise focus path; the existing focus coverage continues to exercise worktrees, plain folders,
  Canvas, and closed or minimized main windows.
- Layout and persistence tests cover old JSON defaults, fixed UUID persistence, disconnect
  fallback and reconnect recovery, notched geometry, floating-pill geometry, and negative screen
  coordinates.
- Manual verification on an external MateView covered the floating pill, secondary roster,
  windowless persistence, **Open Prowl**, and entry-driven restoration and focus.

## Verification limits

The connected Mac exposed only the external MateView during manual verification, so a physical
built-in notch was not available. Stage Manager and cross-Space/fullscreen transitions were not
toggled during the run. Their geometry and selection rules are covered by tests, and the panel's
AppKit collection behavior is configured for those environments, but they remain candidates for
hardware-level release verification.

## Deviations from plan

- No separate navigation helper was introduced in `RepositoriesFeature`: forwarding the island
  action to the existing `entryTapped` action after surfacing Prowl provides a smaller single
  focus path with the same behavior.
- Manual coverage was completed on the available external display; physical-notch and Stage
  Manager checks remain release verification items as described above.

## References

- Primary PR: TBD
- Plan: [000-plan.md](000-plan.md)
- User manual: [Agent Island](../../docs/components/agent-island.md)
