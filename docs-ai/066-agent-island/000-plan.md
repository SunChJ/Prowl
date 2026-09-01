# 066 — Agent Island: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-09-01 |
| **Primary PRs** | [#753](https://github.com/onevcat/Prowl/pull/753) |
| **Related** | [029-active-agents-panel](../029-active-agents-panel/000-plan.md), [036-window-management-hardening](../036-window-management-hardening/000-plan.md), [064-agent-completion-signals](../064-agent-completion-signals/000-plan.md), `docs/components/active-agents.md` |

## Background

Active Agents is currently confined to Prowl's sidebar. It already owns the canonical
per-pane roster and the Working, Blocked, Done, and Idle presentation states, but it cannot
surface that state while another application is in front. The requested extension is a
Notchy-style top-of-screen island that remains useful on both notched and external displays
without introducing another agent lifecycle model.

## Goals

- Present Working agents as a low-priority compact carousel.
- Present Blocked and unviewed Done entries as strong callouts whose lifetime is governed by
  the existing Active Agents state transitions.
- Open a secondary island containing the same rows and actions as the sidebar panel, including
  Idle entries and a persistent Open Prowl action.
- Focus the exact worktree, tab, and pane after surfacing Prowl when an island row is selected.
- Support automatic or user-selected display placement, with notch-aware and floating-pill
  geometry, Spaces, fullscreen applications, Stage Manager, and display hot-plugging.

### Non-goals

- A fifth agent state, a parallel acknowledgement model, or a second roster.
- Inline permission approval or arbitrary terminal input from the island.
- Treating an ambiguous agent disappearance as a failure.
- Multiple synchronized islands, per-display island instances, or configurable island metrics.

## Design / Approach

`ActiveAgentsFeature` remains the single source of truth. Its state gains only presentation
state for the island: expanded/collapsed mode, hover state, and the current Working carousel
anchor. A test-clock-driven effect advances among Working entries every four seconds, pauses
while hovered or expanded, and selects the most recently changed Working entry immediately.

Blocked and Done callouts are pure projections of `ActiveAgentEntry.displayState`. Blocked
sorts before Done and recency breaks ties. No island-specific dismissal mutates or masks those
states: Blocked disappears when the agent leaves that state, Done disappears when existing
`seen` handling turns it into Idle, and removed entries disappear with the roster.

The sidebar and island share one extracted list-content view and row-display resolver. Island
selection first asks `AppLifecycleClient` to surface the singleton main window, then dispatches
the same Active Agents selection action used by the sidebar. The secondary island adds an Open
Prowl control that surfaces the window without changing the selected agent.

A single main-actor observable AppKit controller owns a borderless nonactivating panel. It
hosts SwiftUI content scoped to Active Agents, anchors the panel at the selected screen's top
center, and grows downward. Notched screens use the safe-area geometry to merge with the
hardware cutout; other screens use a floating pill below the visible top edge. The controller
repositions for main-window movement, screen changes, and display reconnection while keeping
the panel out of app/window switching.

Global settings add an enabled flag and a display preference. Automatic placement follows
the main Prowl window, then falls back to a built-in notched screen, the main screen, and the
first connected screen. An explicit display stores its stable CoreGraphics UUID and last
known name; if absent, placement temporarily follows Automatic and returns when it reconnects.

## Alternatives & decisions

- A separate island reducer with a mirrored roster was rejected because it could diverge from
  Active Agents and duplicate handled/unhandled semantics.
- Direct Allow/Deny controls were rejected because agent runtimes do not share a safe reply
  protocol; the island navigates to the source pane instead.
- One panel per screen was rejected in favor of one selectable target to avoid duplicated
  attention and ambiguous interaction state.
- A SwiftUI scene was rejected because precise nonactivating panel level, collection behavior,
  screen anchoring, and outside-click handling require AppKit ownership.

## Amendments

- 2026-09-01 — Built-in display validation showed that a notch boolean was insufficient: the
  compact HStack could place labels behind the physical camera housing. The screen descriptor
  now retains the cutout rectangle derived from macOS auxiliary menu-bar areas. The panel aligns
  to that rectangle, and compact content uses equal left and right wings around an exact-width
  exclusion zone.
- 2026-09-01 — The island-specific Working spinner was replaced by a Heixiu cat-and-tail animation
  that connects the feature to Prowl's cat identity. See
  [002-heixiu-working-animation.md](002-heixiu-working-animation.md).
- Updated 2026-09-01: Heixiu became the persistent island identity and its tail now projects real
  Agent icons with state lamps instead of becoming an anonymous loading ball — see
  [003-agent-icon-tail-projection.md](003-agent-icon-tail-projection.md).
