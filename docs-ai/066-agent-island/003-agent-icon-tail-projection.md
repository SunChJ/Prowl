# Agent Icon Tail Projection

## Context

The first Heixiu follow-up treated the cat as a replacement for the Working spinner: its tail
periodically detached into an anonymous black ball. That model was too close to a loading
animation and failed to explain the actual product state when several agents were present.

Heixiu should be the island's persistent identity. The tail should project the agents themselves,
while each agent icon remains responsible for communicating its Active Agents state.

## Change

- Replace `HeixiuWorkingIndicator` and its anonymous ball cycle with a persistent
  `HeixiuAgentTrail`.
- Render the real runtime icons for up to three roster entries along Heixiu's tail. When more
  entries exist, keep two icons visible and show a `+N` overflow marker.
- Keep every icon on its own light circular plate instead of enclosing the whole projection in
  a shared capsule. Render Heixiu as a black silhouette with a subtle light keyline so the cat
  and its connecting tail stay visible against the black island body.
- Prioritize projected icons by `Blocked`, `Done`, `Working`, then `Idle`, with recency inside each
  state. This prevents an attention state from disappearing behind compact overflow.
- Add a reusable status lamp to each agent icon. Its state language remains the canonical
  `Working / Blocked / Done / Idle`, represented by a system-orange paw, system-red exclamation,
  system-blue sparkle, and secondary sleeping moon.
- Give the compact status pills the same symbol language instead of another loading spinner.
- Let Heixiu's aggregate pose follow the highest-priority projected state: alert for Blocked,
  celebratory for Done, prowling for Working, and sleeping for Idle.
- Keep the existing Working-name carousel, Blocked/Done strong callouts, handled-state lifetime,
  navigation, and expanded-roster behavior unchanged.
- Keep Reduce Motion free of continuous animation. Agent replacement uses a fade instead of a
  scale transition when Reduce Motion is enabled.

This supersedes the visual approach described in
[002-heixiu-working-animation.md](002-heixiu-working-animation.md); that document remains as the
implementation history of the rejected loading-level interpretation.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
