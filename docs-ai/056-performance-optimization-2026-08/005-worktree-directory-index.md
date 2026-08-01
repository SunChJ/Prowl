# 056.005 — Cached Worktree Directory Index

## Context

Active Agents rows derive their displayed repository and branch from the agent pane's current
working directory. Before #648, every row scanned every repository worktree and repeatedly called
`PathPolicy.normalizeURL`, including filesystem existence checks and symlink resolution, from the
sidebar render path.

The author sampled a working instance with six agents and 34 terminal surfaces and attributed
2,253 of 4,711 samples to `SidebarListView.resolveWorktreeID`. A subsequent build removed that
symbol from the profile and reduced `SidebarListView.body` from 51% to 2.4% of main-thread samples.
The workloads were not identical, and this review verified the structural hot path rather than
reproducing those percentages.

## Change

- #648 introduces `WorktreeDirectoryIndex`. Candidate repository and worktree directories are
  normalized into a component-keyed dictionary; lookups normalize the queried directory once and
  walk upward until the deepest indexed path matches.
- Component keys preserve the prior containment semantics without raw-prefix errors such as
  matching `/tmp/repo2` to `/tmp/repo`. Registration order preserves the previous winner when two
  entries normalize to the same depth and path.
- `WorktreeDirectoryIndexCache` reuses the index when repository IDs and stored directories do not
  change, avoiding repeated candidate normalization on ordinary SwiftUI invalidations.
- The original cache treated canonical paths as a pure function of the stored URL. That is false
  for a plain-folder root that is a symlink: retargeting it in place leaves `(id, URL)` unchanged
  while `PathPolicy.normalizeURL` produces a new path. The fork follow-up immediately rebuilds for
  repository-set changes and otherwise revalidates canonical candidate paths at most once per
  second. A changed target rebuilds the index from the already-normalized signature.

## Refs

- Original PR #648
- Original implementation commit `246373b6`
- Fork follow-up commit `b39b7ff4`
- Detailed performance record:
  [032.003](../032-performance-hardening/003-sidebar-agent-row-resolution.md)

## Current state

Row-display batches share one cached index, replacing the former
`agents × candidate directories` scan with one queried-directory normalization per row and
dictionary probes. Candidate canonicalization occurs when repository paths change and, for
external filesystem changes, no more than once per second while renders continue.

The one-second cadence is an explicit correctness/performance tradeoff: a live plain-folder
symlink retarget can keep the previous association until the first render at or after the next
validation boundary, but it no longer remains stale until an unrelated repository change or app
restart. The original before/after profile predates this review addition, so its bounded cost has
not been independently sampled.

## Verification

- The original focused worktree-index, row-display, repository-section, and CLI suites passed 12
  tests before the follow-up.
- A symlink-retarget test was added first and failed to compile until the cache accepted an
  injectable `ContinuousClock.Instant`.
- `WorktreeDirectoryIndexTests` then passed 10 tests, including a real temporary symlink retarget
  driven across the validation boundary without sleeping.
- The combined index, active-agent working-directory, repository-section, and CLI suites passed 30
  tests with no failures or warnings.
- `make check` passed before integrating the latest `main`.
