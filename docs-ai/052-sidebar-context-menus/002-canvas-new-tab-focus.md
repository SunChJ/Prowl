# 052.002 — Canvas New Tab Focus

## Context

In Canvas, `New Terminal Tab` created its tab concurrently with a worktree-level
focus request. The focus resolver could consume that request against an existing
card before the new tab existed, leaving Canvas focused on the wrong tab.

## Change

- `TerminalClient.createTabInDirectory` creates and selects the tab synchronously
  for the Canvas path, returning its `TerminalTabID`.
- `RepositoriesFeature` sends `newTerminalTabCreatedInCanvas` only after creation,
  then requests `CanvasFocusRequest.Target.tab` for that exact ID.
- The regular tabbed-view path keeps its existing asynchronous command dispatch.

## Refs

PR #614

## Current state

Canvas `New Terminal Tab` now targets the newly created card at the worktree root.
`RepositoriesFeatureTests.newTerminalTabInCanvasCreatesAndFocusesNewCanvasTab`
verifies both the root-directory creation request and the exact-tab focus target.
