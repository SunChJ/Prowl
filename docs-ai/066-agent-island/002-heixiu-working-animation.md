# Heixiu Working Animation

## Context

Agent Island initially reused the Active Agents bagua spinner for its compact Working state.
That communicates activity, but it does not give the island a visual identity connected to
Prowl's cat icon.

## Change

- Replace only the Agent Island Working spinner with a small native SwiftUI animation inspired
  by Heixiu, the black cat.
- Keep the cat body stable as the low-priority anchor. At intervals, its tail separates, curls
  into a small black ball, drifts briefly, and reconnects.
- Render the black silhouette against a subdued system-white backdrop so it remains
  legible on the island's black surface without adding a custom color asset.
- Keep Active Agents rows and their existing bagua spinner unchanged; this is an island identity,
  not a new agent state or global status language.
- Under Reduce Motion, render the attached-tail pose without continuous animation.

The animation is driven from a coarse periodic timeline and a deterministic motion projection.
This keeps the always-present Working indicator inexpensive and makes its detach/reconnect cycle
unit-testable without sleeping or snapshot timing.

## Outcome

`HeixiuWorkingIndicator` renders a prowling black-cat silhouette that follows the app icon's
low posture. A 3.6-second deterministic cycle keeps the full tail attached for most of the time,
crossfades it into a detached ball, carries the ball through a short arc, and reconnects it. The
timeline samples at 10 fps rather than refreshing at the display rate.

The silhouette sits on a low-opacity system-white backdrop with a subtle system-orange outline.
This is necessary because the literal black cat and ball would otherwise disappear into the
island's black surface. The indicator is used in both notched and floating compact layouts, while
the shared Active Agents row keeps its existing bagua Working indicator.

## Verification

- Unit coverage checks the attached, detaching, separated-ball, reconnecting, looping, and
  negative-reference-time projections.
- A four-pose native SwiftUI render confirmed that the crouched cat, detached black ball, and
  reconnecting tail remain legible on a black island surface.
- `make check` passed full-tree swift-format lint, strict SwiftLint, and 82 project checks.
- `make test` passed 2,941 app tests plus the 2-test secondary suite with zero failures.
- `make build-app` completed with zero errors and zero warnings.

## References

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
