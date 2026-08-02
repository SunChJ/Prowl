# 056.009 — Working-Directory Resolution Memo

## Context

The cached `WorktreeDirectoryIndex` removed repeated candidate canonicalization, but every Active
Agents row still normalized its working directory against the filesystem on every overlay render.
The author measured a small 0.11–0.26% core cost; the more important boundary is that synchronous
filesystem lookup should not remain proportional to agent rows in a main-thread render path.

## Change

- #659 adds a 256-entry resolution memo keyed by the working directory as asked for, including
  negative results. Repository-set changes and canonical-path revalidation clear the memo before
  a lookup can reuse it.
- The one-second revalidation added in #655 remains the maximum stale window for both index and
  memo when a plain-folder symlink is retargeted in place.
- Fork integration #663 adds a batch API. `SidebarListView.activeAgentRowDisplays` validates the
  repository signature once, then resolves all row directories against that index and memo.
- CLI and other single-lookup callers retain their previous throwaway-index behavior instead of
  acquiring new global-cache semantics.

## Refs

- Original PR #659
- Fork integration PR #663
- Original implementation commit `549b1c20`

## Current state

Ordinary overlay renders pay neither repeated filesystem normalization for stable directories nor
one repository-signature build per row. The memo clears wholesale at its cap; pressure therefore
degrades to the pre-memo lookup cost without changing resolution results.

## Verification

- A new batch-API test failed to compile before the API existed, then covered nested, outside,
  and duplicate directories.
- The focused index, row-display, working-directory, and CLI suites passed 35 tests after merging
  current `main`. The Xcode dependency scan emitted five third-party package warnings; the final
  `make check` and `make build-app` runs completed with no warnings or errors.

