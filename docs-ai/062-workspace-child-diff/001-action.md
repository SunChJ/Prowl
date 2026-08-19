# 062 — Workspace Child Per-Repository Diff: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-19 | Plan aligned with onevcat (⌘⇧Y follows selected child; Outgoing Changes included; Hunk runs in workspace terminal with child cwd; natural degradation, no pre-checks) | tracker relay-tracker#154, issue #616 |
| 2026-08-19 | Implemented `DiffTarget` routing end to end, with tests and `docs/` updates | #704 |

## Outcome & current state (as of 2026-08-19)

- `supacode/Domain/DiffTarget.swift` — `DiffTargetID` (`worktree` / `workspaceChild`,
  child keyed by working-directory path) and `DiffTarget` (git `workingDirectory`,
  `branchName`, `repositoryRootURL`, `terminalHost`, `terminalWorkingDirectory`), plus
  `DiffTarget(worktree:)`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift` —
  `diffTarget(for:)` (child branch falls back live → metadata → repository name; terminal
  host is the synthesized workspace worktree via `plainFolderWorktree(for:)`) and
  `selectedDiffTargetID` (selected worktree, else selected workspace child).
- `RepositoriesFeature.Delegate.showDiff` / `.showOutgoingChanges` carry `DiffTargetID`;
  `WorkspaceChildRowsView` + `RepositorySectionView` wire the child badge and new
  **Show Diff** / **Show Outgoing Changes** context-menu items.
- `AppFeature` / `AppFeature+CommandPalette` resolve targets through `diffTarget(for:)`;
  `SidebarCommands` and the palette item builder gate the two diff view items on
  `selectedDiffTargetID` (navigation/action items keep the worktree gate).
- `ExternalDiffToolClient` and `OutgoingChangesClient` take `DiffTarget`;
  `ExternalDiffSnapshotClient` takes the working-directory `URL`. Hunk sends
  `.createTabWithInput(terminalHost, workingDirectory: terminalWorkingDirectory, …)` and
  names the tab `Hunk Diff · <folder>` when a cwd override is present. The
  `pullRequestInfo` lookup in `supacodeApp.swift` dispatches on `DiffTargetID`
  (`worktreeInfoByID` / `workspaceChildInfoByID`).
- `WorktreeRow` renders the `+N/-M` badge as plain text (no button, no "Show Diff" help)
  when `onDiffTap` is nil.
- Docs: `docs/components/workspaces.md` and `docs/components/diff-view.md` describe the
  child entry points and the workspace-root availability rule.

## Deviations from plan

None known.

## Open questions

None.
