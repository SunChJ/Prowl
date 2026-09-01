# 066.005 — Island-owned Agent Rings

> [006-sidebar-restoration-and-attention-collection.md](006-sidebar-restoration-and-attention-collection.md)
> completes the isolation boundary by restoring the pre-island sidebar row and panel code in
> full. The compact runtime-icon and fluid-ring design in this amendment remains current.

## Context

The AppIcon-derived cat improved brand recognition, but it still competed with the information
the compact island exists to convey. The accompanying `AgentStatusIcon` styling also changed a
shared Active Agents component, expanding a compact-island design decision into sidebar and
attention-card presentation.

Agent Island should remain a projection of Active Agents data without changing how other Active
Agents surfaces render that data. Runtime identity and status are sufficient visual subjects in
the compact trailing area.

## Change

- Restore shared `AgentStatusIcon` behavior unchanged for sidebar rows and attention cards.
- Keep the new visual component private to Agent Island's compact projection.
- Remove the decorative cat and present only the projected runtime icons.
- Increase compact runtime-icon size while preserving the existing priority, recency, and `+N`
  projection rules.
- Encode state in the icon outline: Idle uses a quiet static ring; Working, Blocked, and Done use
  state-colored angular gradients that circulate continuously around the icon.
- Keep the runtime glyph and background visually restrained so the moving ring, rather than a
  bright plate or separate badge, carries status.
- Stop continuous ring motion under Reduce Motion while retaining the state color and outline.
- Do not change Active Agents lifecycle, shared rows, attention cards, navigation, reducer state,
  or island window behavior.

This supersedes the decorative silhouette and shared-icon styling in
[004-app-icon-silhouette-and-motion.md](004-app-icon-silhouette-and-motion.md), while retaining
its constraint that compact animation is a projection of existing Agent state rather than a
loading indicator.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
