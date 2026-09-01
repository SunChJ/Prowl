# 066.007 — Direct Expansion and Trailing Overflow

## Context

The secondary island used a top-edge move transition while its hosting panel changed height. The
combination made the roster appear to pass through the compact island instead of unfolding from
it. The compact icon cluster also placed `+N` as a leading circular item, which read as another
Agent and reversed the intended recency direction.

## Change

- Remove custom movement, scale, fade, and spring transitions from secondary roster expansion and
  attention collection replacement. Let the island adopt its expanded or compact layout directly.
- Treat the projection array as its visual left-to-right order; do not reverse it during layout.
- Place all non-Idle entries before Idle entries. Within each group, order by `lastChangedAt`
  descending so the most recently active Agent is leftmost and Idle naturally settles to the
  right.
- Keep three complete Agent icons visible when the roster overflows. Render only the remaining
  count as a small unoutlined trailing-lower label, so four Agents appear as three icons plus `+1`
  without a leading pseudo-icon.
- Keep the state rings, attention collection, Active Agents lifecycle, and original sidebar
  implementation unchanged.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)

## Verification

- Projection tests cover recent-first and Idle-last ordering, three visible overflow icons, and
  exact remaining counts.
- The targeted `AgentIslandIconClusterTests` suite passes with five tests and zero warnings.
