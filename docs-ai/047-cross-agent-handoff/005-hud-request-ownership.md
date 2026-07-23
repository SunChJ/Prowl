# 047.005 — HUD Request Ownership and Commit Boundary

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-21 |
| **Primary PRs** | #607 |
| **Related** | [047 plan](000-plan.md), [047.004](004-inline-handoff-redesign.md), `docs/components/handoff.md` |

## Context

The inline HUD path in 047.004 injects a real `prowl handoff` request into the live
source agent, then observes a CLI completion by source pane and action. Its fork and
context-only fallbacks start independent transitions while that injected request remains
queued. If the source agent later consumes the request, both paths transition the same
artifact and can launch two receivers. Pane/action matching can also let an unrelated
handoff from the source pane satisfy the HUD. Finally, fallback cancellation is only safe
while collecting a fork briefing; once persistence begins, unstructured detached work can
complete after the UI claims cancellation.

## Goals

- Authorize exactly one transition for an injected HUD request.
- Correlate HUD completion to the exact request and intended destination.
- Keep ordinary CLI handoffs independent of HUD request bookkeeping.
- Make fallback cancellation truthful: cancellable while gathering a briefing, non-cancellable
  once the artifact transition commits.

### Non-goals

- Change the public handoff artifact format or source-pane resolution.
- Cancel a user-dismissed inline request; dismissing the waiting HUD intentionally leaves that
  request running headlessly.

## Design / Approach

- Generate a request UUID when the HUD injects a command and include it in the injected CLI
  invocation. Thread the optional ID through `HandoffInput` and `HandoffCLICompletion`.
- Add one main-actor request registry shared by the HUD and `HandoffCommandHandler`. It
  atomically moves a registered request from `pending` to either `claimed` by its CLI handler
  or `superseded` by a HUD fallback. A rejected CLI claim returns before briefing collection or
  filesystem side effects.
- The HUD accepts a completion only while it is requesting, when the request IDs and intended
  action/destination match, and when an agent transition includes a launched pane.
- Split the fallback into a cancellable briefing-collection phase and an explicit finishing
  phase. The reducer enters finishing before archive/write/save/log/launch work begins, removes
  the Cancel affordance, and launches a non-cancellable persistence effect. The transition
  completes as one unit after that boundary.

## Alternatives & decisions

- **Pane/action plus destination matching only** — rejected: it cannot reject a delayed queued
  request after fallback commits, and unrelated manual commands remain ambiguously correlated.
- **Best-effort cancellation checks around detached filesystem work** — rejected: a check after
  archive/write can leave an artifact transition without its receiver or log. A visible commit
  boundary preserves a consistent outcome.
- **Removing fallbacks** — rejected: fork and context-only remain necessary rescue paths when a
  source agent is wedged or unavailable.

## Verification

- `HandoffHudFeatureTests`, `HandoffCommandHandlerTests`, and
  `HandoffRequestRegistryTests` pass (41 tests): request supersession, exact completion
  correlation, and the non-cancellable finishing phase are covered.
- `AppFeatureHandoffTests` pass (9 tests), exercising injected request correlation through the
  app reducer.
- CLI build, parser tests, and socket integration tests pass.
