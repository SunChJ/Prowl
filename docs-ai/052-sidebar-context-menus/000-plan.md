# 052 — Sidebar Context Menu Overhaul: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-27 |
| **Primary PRs** | #614 |
| **Related** | [050-sidebar-expand-active-and-worktree-tab-badges](../050-sidebar-expand-active-and-worktree-tab-badges/000-plan.md), `docs/components/repositories-and-worktrees.md` |

## Background

The sidebar is the primary entry point for selecting repositories, worktrees, and agent
run targets, but its context menus lag behind what the rows can already do:

- Worktree rows have no terminal actions (new tab, close all tabs, stop run script) even
  though hover affordances for run-script stop already exist, and the terminal tab bar
  already offers "Close All".
- Repository headers expose `New Worktree` only as a hover-`+` button, not in the context
  menu; plain-folder and workspace headers have no path actions even though their
  `rootURL` *is* the directory the user works in.
- Workspace child rows have no context menu at all.
- The PR badge on a row ("PR #2562 · Mergeable") is display-only; there is no way to open
  the pull request from the sidebar, even though `GithubPullRequest.url` is already
  fetched.
- `WorktreeTerminalState.closeAllTabs()`'s confirmation alert says only "Close Terminal
  Tabs?" with no worktree identity — acceptable from the tab bar, unacceptable from the
  sidebar where the target worktree's tabs may not be visible.

A design review (this entry's planning discussion) settled the object boundary: **path
and terminal actions follow the "runnable directory" capability, not the node level**.
Git repo headers are logical groups (their `rootURL` can be a `.bare` dir) and get no
path actions; worktree rows, plain-folder headers, and workspace headers are directory
objects and do.

## Goals

- Restructure the worktree row context menu into the approved grouped spec (below), for
  both main and non-main worktrees.
- `New Terminal Tab` selects the worktree, then creates a tab cwd'd at the **worktree
  root** (not inheriting the focused surface's cwd, unlike Ghostty's ⌘T), and focuses it.
- `Close All Tabs` reuses `closeAllTabs()` protections; disabled (not hidden) at 0 tabs;
  the confirmation alert names the worktree.
- Repo header menu gains `New Worktree` (git repos); plain-folder and workspace headers
  gain `Copy Path` / `Reveal in Finder`; `Repo Settings` label becomes
  `Repository Settings…`.
- Workspace child rows gain `Copy Path` / `Reveal in Finder`.
- The `PR #N` segment in the row info line becomes a click-through link to the PR URL,
  and worktree rows gain an `Open Pull Request` menu item when PR info exists.

### Non-goals

- Bulk close across selected worktrees or a whole repository (needs an aggregated
  worktree-naming confirmation model first; deferred).
- `Run Custom Command >` submenu (future growth direction).
- A "background tab" variant of New Terminal Tab that does not switch selection.
- `New Terminal Tab` on workspace child rows (their one-bound-tab-per-directory model
  makes a second tab's semantics undefined).

## Menu spec

Worktree row (non-main; main drops Pin/Archive/Delete):

```text
New Terminal Tab
Stop Running Script              ← only while a Prowl run script is tracked
────────────────
Pin to Top / Unpin
────────────────
Copy Path
Copy Branch Name
Reveal in Finder
Open Pull Request                ← only when info.pullRequest exists
────────────────
Show Diff
Show Outgoing Changes
────────────────
Close All Tabs                   ← disabled at 0 tabs; not styled destructive
Archive Worktree                 ← bulk: "Archive Selected Worktrees"
Delete Worktree (⇧⌘⌫)            ← bulk: "Delete Selected Worktrees"; .destructive
```

`Close All Tabs` sits in the bottom teardown group (escalation ladder: close tabs →
archive → delete) rather than next to `New Terminal Tab`: context menus open with the
first item under the pointer, and a bulk agent-killing action must not live there.
Single-target vs bulk rule: only actions whose titles say "Selected" act on the
multi-selection; everything else acts on the clicked row (existing Copy Path precedent).

Git repo header: `New Worktree` / ─ / `Repository Settings…` / ─ / `Remove Repository`.
Plain-folder and workspace headers: `Copy Path`, `Reveal in Finder` / ─ /
`Repository Settings…` / ─ / `Remove Repository` (unqualified labels — the menu acts on
the clicked node). Workspace child rows: `Copy Path`, `Reveal in Finder`.

## Design / Approach

- `supacode/Features/Repositories/Views/WorktreeRowsView.swift` — rebuild
  `rowContextMenu`; extend menu availability to main-worktree rows (already gated by
  `isRemovable`, which covers transient lifecycle states). New Terminal Tab flows through
  the reducer so selection + tab creation stay ordered: a new `RepositoriesFeature`
  action selects the worktree and effects
  `terminalClient.send(.createTabInDirectory(worktree, directory: worktree.workingDirectory))`
  (command already exists). Close All Tabs calls
  `terminalManager.stateIfExists(...)?.closeAllTabs()` directly, like existing hover
  actions.
- `supacode/Features/Repositories/Views/RepositorySectionView.swift` — branch the header
  context menu by `repository.capabilities.supportsWorktrees` / `isWorkspace` / plain;
  reuse `createRandomWorktreeInRepository` for New Worktree; rename settings labels in
  both the `…` hover menu and the context menu.
- `supacode/Features/Repositories/Models/SidebarPresentation.swift` — add
  `workingDirectory: URL` to `WorkspaceChildRowModel` (source:
  `ResolvedWorkspaceChild.workingDirectory`);
  `supacode/Features/Repositories/Views/WorkspaceChildRowsView.swift` gains the menu.
- `supacode/Features/Repositories/Views/WorktreeRow.swift` — pass the PR URL into
  `WorktreeRowInfoView` and set `.link` on the "PR #N" `AttributedString` segment (keeps
  current secondary color); workspace child rows get the link for free.
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` /
  `WorktreeTerminalState+Surfaces.swift` — extend
  `TerminalCloseConfirmationTarget.tabs(count:)` with the worktree name so
  `closeAllTabs()`'s alert reads "Close All Tabs in “name”?" from every trigger surface.
- Tests: reducer test for the new-tab action (selection + command emission);
  copy tests for the extended confirmation target. Docs: update
  `docs/components/repositories-and-worktrees.md` (+ `docs/components/terminal.md` if it
  describes the close-all alert).

## Alternatives & decisions

- **Terminal submenu vs top-level items**: top-level. Two-to-three items behind a submenu
  hurts discoverability; ~11 items in 5 groups matches Finder-level density. The only
  future submenu candidate is a dynamic `Run Custom Command >` list.
- **`Close All Tabs` placement**: proposal had it at the top paired with New Terminal
  Tab; review moved it to the teardown group (slip-distance from the pointer, frequency,
  escalation-ladder semantics). Kept non-destructive styling to match the tab bar.
- **Hide vs disable at 0 tabs**: disable, per HIG — stable menu shape teaches the
  capability. `Stop Running Script` stays conditional (transient verb, meaningless when
  idle — Finder's Eject precedent).
- **Label `Close All Tabs` vs `Close All Tabs in This Worktree`**: short form; every item
  in this menu acts on the clicked worktree, and `Archive/Delete Worktree` nearby
  disambiguates tabs-vs-worktree. The long form exists only for the canvas tab menu
  where cross-worktree ambiguity is real.
- **New Terminal Tab semantics**: selects + focuses (macOS "Open in New Tab" precedent)
  and pins cwd to the worktree root — Ghostty's default new-tab cwd inheritance is wrong
  in a worktree-jumping context. A non-selecting background variant was rejected for the
  default verb.
- **Git repo header path actions**: rejected — `Repository.rootURL` may be `.bare`
  (`Repository.name(for:)` special-cases it), so the header is not a user-enterable
  directory. Plain folders and workspaces keep path actions because their root is the
  working directory.
- **PR opening**: `.link` on the existing attributed segment beats a separate button
  (no layout change, whole-row tap still selects) — with the context-menu item as the
  reliable/discoverable fallback.

## Amendments

- Updated 2026-07-27: Canvas New Terminal Tab now focuses its exact created tab — see [002-canvas-new-tab-focus.md](002-canvas-new-tab-focus.md).
(append `- Updated 2026-MM-DD: ... — see [00N-topic.md](00N-topic.md)` lines here)
