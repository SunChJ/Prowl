# 032 — Performance Hardening: Plan

|                 |                                                                                                                                                                                                                                                                        |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Status**      | Implemented (retrospective)                                                                                                                                                                                                                                            |
| **Anchor date** | 2026-05-21                                                                                                                                                                                                                                                             |
| **Documented**  | 2026-07-12 (backfilled)                                                                                                                                                                                                                                                |
| **Primary PRs** | #231, #367, #371, #398 (wave 1); #414, #415, #416, #417 (wave 2, see amendment)                                                                                                                                                                                        |
| **Sources**     | PR descriptions, Sentry App Hang evidence quoted in #231, `docs-ai/017-upstream-sync-process/upstream-ledger.md` (2026-06-09 batch)                                                                                                                                    |
| **Related**     | [020-observability](../020-observability/000-plan.md), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md), [030-agent-status-detection](../030-agent-status-detection/000-plan.md) |

## Background

This entry collects the main-thread/performance fixes that hardened Prowl once real-world
telemetry and heavy multi-agent usage exposed hot paths. It came in two waves:

- **Wave 1 (fork-found, 2026-04-21 → 2026-06-06).** The Sentry wiring from
  [020-observability](../020-observability/000-plan.md) surfaced concrete evidence: 30+ App
  Hang issues on `prowl@2026.4.20` shared one breadcrumb pattern — a burst of ~50
  `repositoryPullRequestRefresh*` + ~20 `filesChanged` actions in one runloop tick, then a
  3s+ main-thread hang, with stacks bottoming out in `URL.standardizedFileURL` reached via
  `RepositoriesFeature.State.isMainWorktree(_:)`. That helper was the loop body of four
  sidebar-render call sites, so each view update cost `O(repos × worktrees²)`
  percent-decoding on the main thread (#231). The rest of the wave was found while working
  in adjacent code: a structured-concurrency timeout that could not actually interrupt
  `ShellClient` processes (#371, exposed by #366's PR-refresh soft timeout — see
  [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md)), deprecated FSEvents
  run-loop scheduling (#367), and a SwiftUI lazy-placement cache spin in the sidebar after
  collapsing/expanding long sections (#398).
- **Wave 2 (upstream ports, 2026-06-08).** The 2026-06-09 upstream review batch
  ([017-upstream-sync-process](../017-upstream-sync-process/000-plan.md)) brought a set of
  upstream performance fixes for paths that are near-constant in Prowl's many-agents
  workload: menu-bar rebuild flicker, OSC-9 progress churn, unbounded terminal event
  buffers, and split-tree re-renders (#414–#417). Documented in
  [002-june-upstream-ports.md](002-june-upstream-ports.md).

## Goals

- Eliminate the App Hang storm: no `standardizedFileURL` work in per-render sidebar loops.
- Make structured-concurrency cancellation actually terminate `ShellClient` child
  processes, so soft timeouts (#366) protect the app in production.
- Move FSEvents delivery off the deprecated run-loop scheduling API.
- Stop the sidebar's lazy-layout main-thread spin after collapse/expand of large sections.
- (Wave 2) Bound memory and main-thread churn on agent-hot paths — see amendment.

### Non-goals

- No general performance-metrics infrastructure; each fix was driven by a concrete
  observed symptom (Sentry signature, reproducible freeze, or upstream-diagnosed churn).
- Wave-2 ports were deliberately scoped to the slices the fork needs (e.g. #417 ports only
  the type-erasure removal from upstream #332, not its notification-dot rework).

## Design / Approach

Wave-1 fixes, each independent:

1. **Precompute the main-worktree flag** (#231). Add `isMain: Bool` to `Worktree`
   (`supacode/Domain/Worktree.swift`), computed once in `init` with a stringwise `==`
   fast-path and a `standardizedFileURL` fallback as defense-in-depth (both URL fields are
   already standardized at every production construction site). Reduce
   `RepositoriesFeature.State.isMainWorktree(_:)` to `worktree.isMain`, making all ~10
   call sites O(1) without touching them. `isMain` is derivable from stored properties, so
   `Equatable`/`Hashable` semantics are unchanged. Locked in by `WorktreeIsMainTests`.
2. **FSEvents via dispatch queue** (#367). Replace deprecated
   `FSEventStreamScheduleWithRunLoop` with `FSEventStreamSetDispatchQueue`, keeping the
   stream on the main queue to match the previous scheduling intent.
3. **Cancellation-aware `ShellClient`** (#371). Replace the blocking
   `process.waitUntilExit()` on a detached task with an async `waitForExit(of:)` built on
   `terminationHandler` + `CheckedContinuation` (double-resume guarded by a
   `LockIsolated<Bool>`); wrap it in `withTaskCancellationHandler` sending SIGTERM on Task
   cancel; and tear down the process from `continuation.onTermination` when the stream
   consumer goes away. This makes #366's `softTimeout` effective with no changes there.
4. **Sidebar layout** (#398). Replace the sidebar's top-level `LazyVStack` with `VStack`:
   after collapsing and expanding long sections, SwiftUI's lazy placement cache could spin
   on the main thread while scrolling.

## Alternatives & decisions

- **#231 — precompute vs restructure**: consolidating the three `first(where:
  isMainWorktree)` sidebar passes was considered and rejected — once each call is an O(1)
  comparison the cost is negligible, and restructuring risked changing ordering semantics.
  `isMainWorktree(_:)` was kept as a thin wrapper to minimize the diff.
- **#231 — monitored follow-up**: the PR planned a Sentry watch after release, with a
  follow-up pass on `orderedRepositoryRoots()` / `orderedRepositoryIDs()` only if the hang
  signatures persisted. No such follow-up PR exists, implying the signatures cleared.
- **#371 — fix the callee, not the caller**: rather than adding watchdog logic around
  every `ShellClient` call, cancellation was wired end-to-end inside the client so all
  existing consumers (notably the PR-refresh soft timeout) benefit without changes.
- **#398 — eager over lazy**: accepting eager layout of all sidebar rows was judged
  cheaper than SwiftUI's misbehaving lazy placement cache for this content size.

## Amendments

- Updated 2026-06-08: wave 2 — four upstream-ported performance fixes for agent-hot paths
  (#414–#417, from the 2026-06-09 upstream review batch) — see
  [002-june-upstream-ports.md](002-june-upstream-ports.md)
- Updated 2026-07-22: wave 3 — the Active Agents row resolution repeated wave 1's
  `isMainWorktree` failure mode and added blocking filesystem calls to it; replaced with a
  cached `WorktreeDirectoryIndex` — see
  [003-sidebar-agent-row-resolution.md](003-sidebar-agent-row-resolution.md)
- Updated 2026-07-25: wave 4 — with the sidebar fixed, the remaining steady-state CPU split
  between agent detection and SwiftUI graph invalidation. Six fixes: emission dedup on
  `rawState`, isolating the Active Agents panel's `entries` read, caching parsed transcript
  fragments, short-circuiting escape stripping, coalescing emissions driven by animated pane
  titles, and sharing transcript directory walks across panes — see
  [004-agent-detection-steady-state.md](004-agent-detection-steady-state.md)
