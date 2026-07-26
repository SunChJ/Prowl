# 052 — Sidebar Context Menu Overhaul: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-27 | Design review of the proposed menus; object boundary settled (path/terminal actions follow the runnable-directory capability, not the node level); `Close All Tabs` moved to the teardown group | this entry's plan |
| 2026-07-27 | Implemented worktree-row menu regroup + `newTerminalTab` reducer action, header menus, workspace-child menu, PR click-through, worktree-named close confirmation; tests + docs | PR #614 |

## Outcome & current state (as of 2026-07-27)

- `supacode/Features/Repositories/Views/WorktreeRowsView.swift` — worktree row menu is
  now: New Terminal Tab · Stop Running Script (conditional) / Pin (non-main) / Copy Path ·
  Copy Branch Name · Reveal in Finder · Open Pull Request (conditional) / Show Diff ·
  Show Outgoing Changes / Close All Tabs (disabled at 0 tabs) · Archive · Delete.
  Main-worktree rows carry the same menu minus Pin/Archive/Delete (they already passed the
  `isRemovable` gate). `newTerminalTab(for:)` falls back to the normal open-worktree flow
  when the worktree has no tabs (see Deviations).
- `RepositoriesFeature.Action.newTerminalTab(Worktree.ID)`
  (`supacode/Features/Repositories/Reducer/RepositoriesFeature+CoreReducer.swift`) —
  selects the worktree (or canvas-focuses it when Canvas is showing) and sends
  `TerminalClient.Command.createTabInDirectory(worktree, directory: worktree.workingDirectory)`
  so the tab opens at the worktree root instead of inheriting the focused surface's cwd.
- `supacode/Features/Repositories/Views/RepositorySectionView.swift` — hover `…` menu and
  header context menu share one `headerMenuItems` builder: git repos get New Worktree /
  Repo Settings… / Remove Repository; plain folders and workspaces get Copy Path / Reveal
  in Finder instead of New Worktree.
- `supacode/Features/Repositories/Views/WorkspaceChildRowsView.swift` +
  `WorkspaceChildRowModel.workingDirectory`
  (`supacode/Features/Repositories/Models/SidebarPresentation.swift`) — child rows now
  have Copy Path / Reveal in Finder.
- `supacode/Features/Repositories/Views/WorktreeRow.swift` — the `PR #N` info segment is
  an `AttributedString` link to `GithubPullRequest.url` (workspace child rows inherit it);
  the row menu's Open Pull Request reuses
  `.githubIntegration(.pullRequestAction(_, .openOnCodeHost))` with its repo-URL fallback.
- `TerminalCloseConfirmationPolicy.informativeMessage(for:worktreeName:)`
  (`supacode/Features/Terminal/Models/TerminalCloseConfirmationPolicy.swift`) — pure
  message builder; `WorktreeTerminalState` alert bodies now read "… in “name” …" so
  sidebar-triggered closes always identify the target worktree.
- Tests: `supacodeTests/RepositoriesFeatureTests.swift` (3 `newTerminalTab` cases:
  normal, canvas, unknown-worktree) and
  `supacodeTests/TerminalCloseConfirmationPolicyTests.swift` (2 message cases). Docs:
  `docs/components/repositories-and-worktrees.md`, `workspaces.md`,
  `github-pull-requests.md`.

Verified: `make build-app` clean, targeted tests pass (9/9), `make check` clean; debug app
launched via self-verify (CLI list/open OK, no relevant log errors).

## Deviations from plan

- Menu label shipped as **Repo Settings…** instead of the planned "Repository Settings…":
  "Repo Settings" is the established term in the Command Palette and Shelf spine, so only
  the HIG ellipsis was added.
- `New Terminal Tab` on a worktree with zero tabs routes through the ordinary
  open-worktree flow (select + `ensureInitialTab`) instead of `.newTerminalTab`: the
  ensure-initial path already creates the first tab at the root and runs the repo setup
  script, and always sending `.createTabInDirectory` would race it into a duplicate tab.
  The reducer action is only used when tabs exist, where the cwd-inheritance problem
  actually occurs.

## Open questions

- The PR-link segment's styling (secondary color retained despite `link`) and the menu
  interactions were not visually verified end-to-end: the sidebar section with a PR badge
  was collapsed in the debug instance and the agent host lacks Accessibility permission
  for AX-driven clicks. Needs a quick manual right-click pass.
- `.claude/skills/self-verify-prowl/scripts/helpers.sh` `debug_pids` greps
  `Debug/Prowl.app/...` but the debug bundle is `Prowl Debug.app`, so `debug_pids` /
  `debug_window_id` return nothing; worked around by passing the PID explicitly.
