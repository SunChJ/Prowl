# 066.008 — Render and Focus Isolation

## Context

The pre-merge impact audit for PR #753 found no direct changes under the Ghostty terminal
implementation, but identified two indirect risks in the island window:

- island-owned status rings use display-linked SwiftUI `TimelineView` updates at 30 FPS while an
  Agent is Working, Blocked, or Done. Ghostty surface coordination and SwiftUI/AppKit window work
  share the main UI thread, so continuous island view invalidation can compete with terminal
  presentation;
- the nonactivating island panel is allowed to become key. If it takes key-window status from the
  main Prowl window, `WindowFocusObserverView` correctly marks its Ghostty surfaces unfocused even
  though the interaction is only expanding the island.

The same audit found that local and global mouse monitors are installed for the entire app
lifetime, including while Agent Island is disabled, and that the hidden panel still builds its
full SwiftUI content tree. These behaviors are outside the intended opt-in boundary.

## Change

- Keep the fluid state-ring design, but move its rotation to an island-owned Core Animation layer
  so SwiftUI no longer recomputes icon and attention trees on a display-linked schedule.
- Make the nonactivating panel ineligible for key-window status so expanding or collapsing Agent
  Island cannot change Ghostty focus state.
- Build the island UI only while the feature is enabled and the Active Agents roster is non-empty.
- Install outside-click and Escape monitors only while the secondary roster is expanded, then
  remove them immediately on collapse or disable.
- Reduce the transparent panel footprint to the widest currently visible island surface instead
  of retaining the expanded roster width in the compact state.
- Keep all changes inside Agent Island-owned files. Do not modify Ghostty, terminal focus,
  Active Agents sidebar rendering, or Agent lifecycle semantics.

## Verification

- Four targeted isolation tests pass for panel key eligibility, event-monitor lifetime, compact
  panel width, and Core Animation stopping under Idle or Reduce Motion.
- The PR changes no files under `supacode/Infrastructure/Ghostty` or
  `supacode/Features/Terminal`.
- `make check` passes.
- `make test` passes 2,955 app tests plus the 2-test secondary suite with zero failures.
- `make build-app` completes with zero errors and zero warnings.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
