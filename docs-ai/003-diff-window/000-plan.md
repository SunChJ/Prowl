# 003 — Diff Window: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-06 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #1, #10, #45 (follow-up waves: #449, #529, #536, #537, #540) |
| **Sources** | PR descriptions (#1, #10, #45, #449, #529, #536, #537, #540); fork change-list entries for commits `0d03848`–`8985fc2`, `1b32a26` (ledger lives at [017-upstream-sync-process/upstream-ledger.md](../017-upstream-sync-process/upstream-ledger.md)) |
| **Related** | [012-keybinding-system](../012-keybinding-system/000-plan.md), [037-line-diff-tracking](../037-line-diff-tracking/000-plan.md), `docs/components/diff-view.md` |

## Background

Prowl's core loop is "let an agent work in a worktree, then review what it did".
Before this feature there was no in-app way to inspect a worktree's uncommitted
changes — reviewing an agent's output meant switching to a terminal or an
external tool. The fork wanted a fast, local diff viewer reachable directly from
the worktree row.

This is a fork-only feature (upstream supacode has no equivalent), built on
YiTong (`https://github.com/onevcat/YiTong`), onevcat's own WKWebView-backed
diff-rendering library.

## Goals

- A standalone diff window showing all changes in the selected worktree's
  working directory vs **HEAD** — tracked changes and untracked new files.
- File tree sidebar (left) + rendered diff (right) via `NavigationSplitView`,
  with YiTong's `DiffView` as the renderer.
- Instant file switching: preload all file contents concurrently when the
  window opens.
- Openable from the worktree row's diff badge, a keyboard shortcut, and a
  "Show Diff" menu item.
- Toolbar with sidebar toggle and a split/unified diff style picker persisted
  across launches; `Cmd+W` closes the window; window frame persisted.
- Singleton window that refreshes its content when it regains focus.

**Non-goals** (initial scope)

- Diff against a base branch or a PR — this is strictly working-tree vs HEAD.
- External diff tools (added later, see amendment 002).
- Staging/committing from the diff window.

## Design / Approach

As shipped in #1 (2026-03-06):

- **Git layer** — new `GitClient` operations: `git diff HEAD --name-status`
  (changed-file list), `git ls-files --others --exclude-standard` (untracked
  files), and `git show HEAD:<path>` (old file contents). New/deleted/renamed
  files map to empty-vs-disk, HEAD-vs-empty, and old-path-vs-new-path pairs.
- **Model** — `DiffChangedFile` parses the `--name-status` output (M/A/D/R/C
  status plus paths).
- **State** — `DiffWindowState`, an `@Observable` class holding the file list,
  selection, and a per-file `DiffDocument` cache filled by concurrent
  preloading, so selecting a file renders from cache.
- **Window** — `DiffWindowManager`, a singleton `NSWindow` manager following
  the existing `SettingsWindowManager` pattern: one window app-wide,
  `setFrameAutosaveName` for frame persistence, a local `keyDown` event monitor
  to intercept `Cmd+W`, and refresh-on-focus.
- **View** — `DiffWindowContentView`: `NavigationSplitView` with the file list
  sidebar and YiTong `DiffView` detail; toolbar hosts the sidebar toggle and a
  split/unified style picker persisted via `UserDefaults`
  (`@AppStorage("diffViewStyle")`).

Two small fixes were planned/landed as part of the initial arc: unicode
(Chinese) filenames were invisible because git's default `core.quotePath=true`
octal-escapes non-ASCII paths — fixed by passing `-c core.quotePath=false` to
both listing commands (#10); and the YiTong dependency moved from
branch-tracking (`master`) to a semver pin at 0.2.0, whose optimized web bundle
cut the embedded asset from 9.3 MB to 2.7 MB (−7 MB on the .app) (#45).

## Alternatives & decisions

- **Standalone `NSWindow`, not a SwiftUI `WindowGroup` scene** — deliberately
  followed the existing `SettingsWindowManager` singleton pattern. Consequence:
  the window does not inherit SwiftUI environment appearance, which later
  required explicit appearance plumbing (amendment 004).
- **Preload everything on open** rather than load-on-select — chosen for
  instant file switching; acceptable because worktree diffs are typically
  small. The concurrent task group updates the cache per-file as results
  arrive, so early selections don't wait for the whole set.
- **YiTong pinned by semver (0.2.0) instead of tracking `master`** (#45) —
  reproducible release builds and a measured −71% web-bundle size.
- **Diff basis is HEAD, not the base branch** — the window answers "what did
  the agent change that isn't committed yet"; PR-level review is delegated to
  code hosts (see `docs/components/github-pull-requests.md`).

## Amendments

- Updated 2026-06-14: configurable external diff tools (Hunk, FileMerge,
  Kaleidoscope, custom command) — see [002-external-diff-tools.md](002-external-diff-tools.md)
- Updated 2026-07-03: render pipeline hardening — stale-cache race, select
  debounce, render-error recovery, `Debouncer` extraction + `RenderState` enum
  (#529/#536/#537) — see [003-render-pipeline-hardening.md](003-render-pipeline-hardening.md)
- Updated 2026-07-08: diff window follows app appearance instead of system
  (#540) — see [004-appearance-follows-app.md](004-appearance-follows-app.md)
- Updated 2026-07-14: built-in outgoing changes for an identified pull request,
  using its target remote and merge-base semantics — see [005-outgoing-changes.md](005-outgoing-changes.md)
