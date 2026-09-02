# 066 — Agent Island: Plan

| | |
| --- | --- |
| **Status** | Implemented — see [001-action.md](001-action.md) |
| **Anchor date** | 2026-09-01 |
| **Primary PRs** | #753 (original implementation, contributed by @SunChJ); #756 (fork-owned continuation that carries every #753 commit) |
| **Related** | [029-active-agents-panel](../029-active-agents-panel/000-plan.md), [036-window-management-hardening](../036-window-management-hardening/000-plan.md), [064-agent-completion-signals](../064-agent-completion-signals/000-plan.md), `docs/components/agent-island.md` |

## Background

Active Agents lives in Prowl's sidebar. It already owns the canonical per-pane roster and the
Working, Blocked, Done, and Idle presentation states, but it cannot surface that state while
another application is in front. A blocked or finished agent waiting for the user is easy to miss.
The requested extension is a Notchy-style top-of-screen island that is useful on both notched and
external displays without introducing a second agent lifecycle model. It is deliberately a more
intrusive surface than the sidebar, so it ships opt-in and off by default.

## Goals

- Present Working agents as a low-priority compact carousel.
- Present Blocked and unviewed Done entries as stronger callouts whose lifetime is governed by the
  existing Active Agents state transitions.
- Open a secondary roster with the same rows and actions as the sidebar panel, including Idle
  entries and a persistent Open Prowl action.
- Focus the exact worktree, tab, and pane after surfacing Prowl when an island row is selected.
- Support automatic or user-selected display placement with notch-aware and floating-pill
  geometry, Spaces, fullscreen applications, Stage Manager, and display hot-plugging.

### Non-goals

- A fifth agent state, a parallel acknowledgement model, or a second roster.
- Inline permission approval or arbitrary terminal input from the island.
- Treating an ambiguous agent disappearance as a failure.
- Multiple synchronized islands, per-display instances, or configurable island metrics.

## Design / Approach

`ActiveAgentsFeature` (`supacode/Features/ActiveAgents/Reducer/ActiveAgentsFeature.swift`) stays
the single source of truth. Its state gains only presentation fields — `isIslandEnabled`,
`isIslandRosterExpanded`, `isIslandHovered`, `islandCarouselEntryID` — plus a
`continuousClock`-driven effect that advances among Working entries every four seconds, pauses
while hovered or expanded, and jumps to the most recently changed Working entry. The effect is
rebuilt only when the ordered Working membership or one of those gates changes, so per-second
title refreshes never restart it. `islandWorkingEntries` and `islandAttentionEntries` are derived
projections of `displayState`; nothing island-specific mutates or masks an entry.

Island-originated actions (`islandEntryTapped`, `islandHandOffTapped`,
`islandRunWorkflowTapped`, `islandOpenProwlTapped`) collapse the roster in the reducer and are
intercepted by `AppFeature` (`supacode/Features/App/Reducer/AppFeature.swift`), which surfaces the
main window through `AppLifecycleClient` and then forwards to the unchanged sidebar action so
focus, the handoff HUD, and workflow start stay single-sourced. `agentIslandEnabled` is mirrored
into the reducer from settings the same way `showActiveAgentTabTitles` already is.

`AgentIslandWindowController`
(`supacode/Features/ActiveAgents/BusinessLogic/AgentIslandWindowController.swift`) owns one
borderless, nonactivating `NSPanel` that cannot become key or main, sits one level above the menu
bar, joins all Spaces and fullscreen applications, and hosts `AgentIslandView` scoped to the app
store. Outside-click monitors and a low-frequency Escape key-state poll exist only while the
roster is expanded. `supacode/Features/ActiveAgents/Models/AgentIslandScreen.swift` holds the
pure geometry (`AgentIslandScreenLayout`: cutout rectangle from the screen's auxiliary menu-bar
areas, display resolution order, panel frame) and `AgentIslandDisplayCatalog`, which keys screens
by CoreGraphics display UUID and refreshes on screen-parameter changes.

The views under `supacode/Features/ActiveAgents/Views/` are island-owned: `AgentIslandView`
(compact bar with equal wings around the physical cutout, attention collection, roster
container), `AgentIslandIconCluster` (up to three runtime icons, recent non-Idle first and Idle
last, `+N` overflow, Core Animation state rings), `AgentIslandAttentionCollection` (one or two
columns, three rows before scrolling), and `AgentIslandRosterContent` (composes the sidebar's
`ActiveAgentRow`, content-sized up to a 360pt cap). Sharing with the sidebar is deliberately
narrow: `ActiveAgentRowSupport.swift` extracts `ActiveAgentRowPresentation` (subtitle, help, pane
title, Workflow badge) and `ActiveAgentRowContextMenu` for both `ActiveAgentsPanel` and the island
roster; the sidebar's row and panel layout are otherwise untouched.

Settings add `agentIslandEnabled` (default `false`) and `agentIslandDisplayPreference`
(`AgentIslandDisplayPreference`: `.automatic` or `.display(id:name:)`) to `GlobalSettings`, with a
section on Settings › Notifications (`AgentIslandSettingsSection`). Automatic follows the Prowl
window's display, then a built-in notched display, the macOS main display, then the first screen.
A fixed display stores its UUID plus last-known name; when absent, placement follows Automatic
until it reconnects. The picker matches by UUID only (`AgentIslandDisplaySelection`).

## Alternatives & decisions

- **Separate island reducer with a mirrored roster** — rejected: it would diverge from Active
  Agents and duplicate handled/unhandled semantics.
- **Inline Allow/Deny controls** — rejected: agent runtimes share no safe reply protocol; the
  island navigates to the source pane instead.
- **One panel per screen** — rejected in favor of one selectable target.
- **SwiftUI scene** — rejected: level, collection behavior, screen anchoring, and outside-click
  handling need AppKit ownership.
- **Notch as a boolean** — replaced by the measured cutout from `auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea` after labels landed behind the camera housing on a built-in display.
- **A cat mascot as the island identity** — three iterations were built and removed inside #753:
  a "Heixiu" black-cat silhouette whose tail detached into a drifting ball as the Working loop, a
  tail that projected agent icons with state lamps and a pose following the top state, and an
  AppIcon-derived mint silhouette. Each competed with the status information the compact bar
  exists to convey. Final: runtime icons with state-colored rotating rings, nothing decorative.
- **Single attention card plus `+N`** — rejected for a per-entry collection so every Blocked or
  Done agent stays individually actionable.
- **SwiftUI `TimelineView` at 30 FPS for the rings** — replaced by island-owned Core Animation
  layers so continuous invalidation stays off the main thread shared with Ghostty.
- **Key-eligible panel** — forbidden so expanding the island cannot demote Ghostty surface focus.
- **Global keyDown monitor for Escape** — needs Accessibility/Input Monitoring; a combined-session
  `CGEventSource.keyState` poll, active only while expanded, was chosen instead.
- **Toolbar button or dedicated settings destination** — rejected; opt-in section in
  Notifications.
- **Custom expansion transition** — removed; the roster appears directly while the panel resizes.

## Amendments

- Updated 2026-09-02: continuation on #756 — hover flag reset when the roster empties, display
  picker matched by UUID, unrelated formatting churn reverted, and the former working-note
  amendments (002–010) folded into this plan and [001-action.md](001-action.md).
