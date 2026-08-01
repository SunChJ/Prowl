# 032.003 — Sidebar Agent Row Resolution

## Context

Wave 1 of this entry fixed `RepositoriesFeature.State.isMainWorktree(_:)`, where
`URL.standardizedFileURL` ran `O(repos × worktrees²)` times per sidebar render on the main
thread (#231). The Active Agents panel later grew its own resolution path with the same
shape, and it went further by touching the filesystem rather than only decoding strings.

A 10-second `sample(1)` of a running Debug build with 6 Codex sessions and 34 terminal
surfaces attributed 2253 of 4711 samples — roughly half of all process CPU — to
`SidebarListView.resolveWorktreeID(forWorkingDirectory:in:)`. The main thread was on-CPU for
4203 of those samples. `stat` and `__getattrlist` ranked among the top non-blocking leaf
frames, alongside Foundation's URL path-normalization internals
(`String._removingDotSegments`, `_hasDotDotComponent`, `_compressingSlashes`).

The reported symptom was twofold: sustained high CPU whenever agents streamed output, and a
roughly one-second delay between creating a worktree and its row appearing in the sidebar.

## Root cause

`SidebarListView.activeAgentRowDisplays(entries:repositories:metadata:)` called
`resolveWorktreeID` once per agent row, and each call scanned every worktree of every
repository. Per candidate pair it invoked `PathPolicy.normalizeURL` three times — twice
inside `PathPolicy.contains(_:in:)` and once for the depth comparison.

`PathPolicy.normalizeURL` (`supacode/Support/PathPolicy.swift`) performs a
`FileManager.fileExists` check followed by `resolvingSymlinksInPath()`, which issues one
`getattrlist` per path component. So every `(row, worktree)` pair cost two blocking
filesystem round-trips, inside a SwiftUI `body` getter that re-runs on every agent output
tick.

The worktree-creation lag had the same origin rather than a slow `wt` subprocess.
`insertWorktree` mutates `state.repositories` synchronously
(`supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeState.swift`), and the
same reducer case also fires `.reloadRepositories(animated:)`
(`supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeCreation.swift`). Both
invalidations forced a full rescan before the sidebar could paint, and the new worktree
permanently lengthened the inner loop.

## Change

`supacode/Domain/WorktreeDirectoryIndex.swift` introduces two types:

- `WorktreeDirectoryIndex` normalizes each candidate directory once into a dictionary keyed
  by joined path components. A lookup normalizes the queried directory once, then walks it
  upward one component at a time and returns the first hit, so the deepest containing
  directory still wins. Keys compare whole components rather than raw string prefixes, which
  keeps `/tmp/repo` from matching a sibling `/tmp/repo2`.
- `WorktreeDirectoryIndexCache` memoizes the index against the `(id, directory)` pairs it was
  built from. Render passes that change only branch names, colors, or icons reuse it. Because
  canonical paths also depend on filesystem state, an unchanged repository set revalidates its
  normalized directories at most once per second and rebuilds if a symlink target changed.

`SidebarListView.activeAgentRowDisplays` now resolves the index once for the whole batch.
`resolveWorktreeID` is kept as the public entry point and delegates to the cache.

Per sidebar render the cost drops from `agents × worktrees × 3` calls to `normalizeURL` — two
filesystem round-trips each — to one queried-directory normalization per agent. Candidate
directories are normalized when the repository set changes and, while it stays stable, no more
than once per second for canonical-path validation. This bounds external symlink-target staleness
without restoring filesystem work to every render pass.

Resolution semantics are unchanged, including the pre-existing asymmetry where a
non-existent path skips symlink resolution while an existing one does not. The 13 sidebar
tests in `supacodeTests/RepositorySectionViewTests.swift` pass unmodified.

## Refs

PR #648, implementation commit `246373b6`.

## Current state

`supacode/Domain/WorktreeDirectoryIndex.swift` owns the resolution. Ten tests in
`supacodeTests/WorktreeDirectoryIndexTests.swift` cover nested resolution, deepest-match
preference, the sibling-prefix trap, plain-folder repositories, unmatched paths, the empty
index, `..` normalization, repository-set invalidation, branch-only reuse, and live symlink
retargeting after the bounded revalidation interval.

`make build-app` reported 0 errors and 0 warnings, `make test` reported 1943 passing tests
and 0 failures, and `make check` (swift-format strict lint plus SwiftLint) was clean.

The reduction was measured on a live instance after swapping in the fixed build. Two 10-second
`sample(1)` runs, before and after, on comparable workloads:

| Main-thread measure           |     Before |      After |
| ----------------------------- | ---------: | ---------: |
| `resolveWorktreeID` samples   | 2253 (48%) | 0 (absent) |
| `SidebarListView.body`        | 2382 (51%) | 183 (2.4%) |
| `GraphHost.flushTransactions` | 3774 (80%) | 1530 (20%) |
| Idle in `mach_msg2_trap`      |       ~11% |        53% |

Process CPU fell from 94–134% to 29–70%. The workloads were not identical — 34 surfaces and 6
sessions before versus 23 surfaces and 8 sessions after — so the percentages are indicative
rather than a controlled comparison; the disappearance of `resolveWorktreeID` from the profile
is not. The only residual frames are 24 samples (0.3%) in `WorktreeDirectoryIndex.worktreeID`,
which is the by-design single normalization of the queried directory per lookup. This profile
predates the once-per-second canonical revalidation added during review; that bounded validation
cost has not been independently sampled.

## Recurrence note

This is the third instance in this entry of the same failure mode: path normalization
performed per-item inside a sidebar render pass. `standardizedFileURL` and
`resolvingSymlinksInPath()` are not cheap accessors — the latter is a syscall per path
component. New sidebar-render code should resolve paths through a precomputed index rather
than normalizing inside a loop.
