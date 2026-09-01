# 066 — Agent Island: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-09-01 | Implemented the Active Agents-backed Agent Island, shared roster UI, display placement settings, navigation reuse, and regression coverage. | [#753](https://github.com/onevcat/Prowl/pull/753), [000-plan.md](000-plan.md) |
| 2026-09-01 | Corrected built-in notch layout to reserve the physical camera cutout instead of treating notch presence as a boolean. | [#753](https://github.com/onevcat/Prowl/pull/753) |
| 2026-09-01 | Replaced the island Working spinner with the Heixiu cat-and-detaching-tail animation. | [002-heixiu-working-animation.md](002-heixiu-working-animation.md) |
| 2026-09-01 | Superseded the anonymous tail ball with real Agent icon projections and cat-like per-Agent status lamps. | [003-agent-icon-tail-projection.md](003-agent-icon-tail-projection.md) |
| 2026-09-01 | Replaced the white icon plates and geometric outline with an AppIcon-derived mint silhouette, dark state nodes, and tail-origin motion. | [004-app-icon-silhouette-and-motion.md](004-app-icon-silhouette-and-motion.md) |

## Outcome

Agent Island now projects the existing Active Agents roster into a single top-of-screen panel.
It does not add an agent state, acknowledgement flag, or lifecycle signal: Working, Blocked,
Done, and Idle remain interpretations of `ActiveAgentsFeature.entries`.

- The compact island shows the most recently changed Working entry, advances through multiple
  Working entries every four seconds, and pauses while hovered or while the roster is open.
  When no entry is Working, the compact area remains available as a neutral agent-count entry
  point. Heixiu remains the visual anchor while its tail projects the real runtime icons for the
  highest-priority roster entries. Each icon uses a low-contrast state-tinted node and compact
  colored status bead. The cat pose follows the highest-priority projected state instead of
  acting as a loading spinner.
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
- `AgentStatusIcon` gives sidebar, attention, and projected icons the same status-lamp language.
  `HeixiuAgentTrail` prioritizes Blocked, Done, Working, then Idle; it keeps up to three separate
  dark runtime-icon nodes visible, replaces lower-priority overflow with `+N`, and joins the
  nearest high-priority icon to Heixiu's tail without a shared loading-track background. The
  filled `ProwlAccent` silhouette follows the AppIcon's low prowling anatomy, while continuous
  tail, head, and foreleg geometry expresses aggregate state.
- `AgentIslandWindowController` owns one transparent nonactivating `NSPanel`. It anchors the top
  edge while content grows downward, joins all Spaces and fullscreen applications, and responds
  to display changes and main-window movement without participating in normal window cycling.
- `AgentIslandScreenLayout` resolves a fixed CoreGraphics display UUID when connected, otherwise
  temporarily follows Automatic placement without erasing the saved selection. Automatic uses
  the Prowl window's display, then a built-in notched display, the main display, and finally the
  first connected display. On a notched screen it derives the physical cutout from
  `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, aligns the panel to its center, and reserves
  the exact cutout width between equal compact-content wings.
- Settings adds **Agents → Agent Island**, enabled by default, with Automatic or fixed-display
  placement. Existing settings JSON decodes to the new defaults.
- Reduce Motion replaces the default spring, scrolling, icon-replacement, and Working-lamp
  transitions with static presentation or opacity transitions.

## Verification

- `make check` — passed: swift-format lint, strict SwiftLint, and project checks.
- `make test` — passed: 2,940 app tests plus the 2-test secondary suite, zero failures.
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
- The notch regression fixture uses the connected built-in display's measured geometry:
  `1512×982`, `32pt` safe-area inset, and a `185×32pt` cutout. Seven targeted screen-layout tests
  pass, including exact auxiliary-area derivation and content exclusion.
- Manual verification on an external MateView covered the floating pill, secondary roster,
  windowless persistence, **Open Prowl**, and entry-driven restoration and focus. A follow-up
  Debug run covered simultaneous Pi and Codex icons in Idle and mixed Working/Idle projections:
  the icons stayed separate, Working moved nearest the tail, its orange lamp remained legible, and
  the compact content fit without right-wing clipping. The AppIcon-derived follow-up was also
  checked with one and two idle agents at native island size: the mint silhouette remained
  readable, the dark nodes removed the previous white mass, and both runtime glyphs remained
  distinct.

## Verification limits

The built-in display was available for physical geometry inspection, but the already-running
Debug instance was not restarted after the fix because it hosted live terminal sessions. The
post-fix layout was therefore verified against its exact `NSScreen` geometry and regression tests
rather than a restarted live panel. Stage Manager and cross-Space/fullscreen transitions were not
toggled during the run; the panel's AppKit collection behavior is configured for those
environments, but they remain candidates for release verification.

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
