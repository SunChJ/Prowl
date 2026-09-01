# AppIcon Silhouette and Tail Motion

> The decorative cat and shared-icon styling in this amendment are superseded by
> [005-island-owned-agent-rings.md](005-island-owned-agent-rings.md). The roster projection,
> priority, and Reduce Motion requirements remain applicable.

## Context

The first Agent-icon projection removed the anonymous loading ball, but its shared visual
language was still wrong. Light circular plates occupied most of the compact trailing wing,
while Heixiu was reduced to a thin geometric outline. At island size this made the runtime icon
look like the subject and the cat look like a secondary diagram.

The Prowl AppIcon already defines the intended character: a low, rounded, prowling cat with an
arched back, grounded paws, a lowered head, pointed ears, and a thick tail. Agent Island should
use a simplified version of that silhouette instead of inventing a second cat anatomy.

## Change

- Replace the outlined geometric cat with a compact filled silhouette derived from the AppIcon's
  proportions: arched back, low head, two ears, four grounded paws, and a thick rounded tail.
- Use the existing `ProwlAccent` mint as the cat fill against the black island. Do not add a white
  keyline around the body.
- Replace light Agent plates with low-opacity, state-tinted nodes and a subtle state ring. Keep
  the actual runtime glyph as the center of each node.
- Treat the lower-right state mark as an indicator lamp. The compact trail uses a colored bead;
  the larger shared Active Agents rows keep their cat-like state symbols and text.
- Make Agent insertion originate at the tail tip with a short spring scale/translation. Working
  uses a quiet breathing node and a small prowling body shift; state changes reshape Heixiu
  instead of running an unrelated loading loop.
- Preserve projection priority, overflow, strong Blocked/Done callouts, navigation, and lifecycle
  semantics.
- Reduce Motion keeps the silhouette and lamps static and replaces tail-origin movement with a
  fade.

This supersedes the white-plate and outlined-cat styling recorded in
[003-agent-icon-tail-projection.md](003-agent-icon-tail-projection.md), while keeping its roster
projection and state-priority model.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
