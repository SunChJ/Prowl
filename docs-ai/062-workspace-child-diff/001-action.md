# 062 — Workspace Child Per-Repository Diff: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-19 | Plan aligned with onevcat (⌘⇧Y follows selected child; Outgoing Changes included; Hunk runs in workspace terminal with child cwd; natural degradation, no pre-checks) | tracker relay-tracker#154, issue #616 |
| 2026-08-19 | Implemented `DiffTarget` routing end to end, with tests and `docs/` updates | #704 |
| 2026-08-20 | Review round (pi agent): scoped child targets by workspace, child `repositoryRootURL` follows recorded source root, added child outgoing coverage | #704 |

## Outcome & current state (as of 2026-08-19)

- `supacode/Domain/DiffTarget.swift` — `DiffTargetID` (`worktree` /
  `workspaceChild(workspaceID:path:)` — children are scoped by workspace because metadata
  does not enforce path uniqueness across workspaces) and `DiffTarget` (git
  `workingDirectory`, `branchName`, `repositoryRootURL`, `terminalHost`,
  `terminalWorkingDirectory`), plus `DiffTarget(worktree:)`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift` —
  `diffTarget(for:)` (resolves within the named workspace; child branch falls back live →
  metadata → repository name; terminal host is the synthesized workspace worktree via
  `plainFolderWorktree(for:)`), `selectedDiffTargetID` (selected worktree, else selected
  workspace child), and `pullRequest(for:)` (per-target PR cache dispatch, wired from
  `supacodeApp`). A child's `repositoryRootURL` is the metadata-recorded local source root
  (`ProjectWorkspaceRepositoryEntry.localSourceURL`) so linked/worktree checkouts pick up
  the source repository's `repositorySettings` and `{repoPath}`; remote clones and
  metadata without a source location fall back to the checkout directory. Chosen over
  runtime `git` root resolution to keep the query synchronous with no extra cached state.
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
