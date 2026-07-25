# 050 — Sidebar: Expand-Active Third State + Per-Worktree Tab Badges: Action

| | |
| --- | --- |
| **Status** | Implemented on `feature/sidebar-expand-active` |
| **Date** | 2026-07-25 |
| **Plan** | [000-plan.md](000-plan.md) — implemented as decided, then revised per PR #612 review (see the plan's Amendments and "Post-review follow-ups" below) |

## What was built

### Expand Active third state (`SidebarListView.swift`)

- `RepositoryListHeaderAction` gained `.expandActive` with `title`
  ("Expand Active"), a dedicated `helpText` ("Expand repositories with open
  tabs"; the other two states keep `title` as help), and zero rotation
  (chevron.right family).
- `repositoryListHeaderAction(expandedRepoIDs:expandableRepositoryIDs:activeRepositoryIDs:)`
  implements the Decisions #2 table as a pure static function. New
  `activeRepositoryIDs(in:expandableRepositoryIDs:terminalManager:)` filters
  expandable repos through `RepositorySectionView.openTabCount > 0`.
- The header button moved out of `SidebarListView.body` into a private leaf
  view `RepositoryListHeaderToggle` (same file). It owns both the
  `WorktreeTerminalManager` read (isolation: the sidebar body never
  subscribes to terminal churn) and the click handler; `.expandActive`
  assigns `expanded = (expanded − expandable) ∪ active` through the existing
  binding in a single write.
- Glyph: `chevron.right.2` (double chevron). Initially shipped as
  `chevron.right` + 4pt accent-dot overlay; replaced post-review — the cycle
  now reads as remaining depth: `»` → `›` → rotated-down chevron.

### Per-worktree tab badges (`RepoHeaderRow.swift`, `WorktreeRow.swift`, `WorktreeRowsView.swift`)

- Extracted the capsule visual into `TabCountBadge(count:)` (hidden at 0);
  `RepoHeaderTabCountBadge` now delegates to it.
- New `WorktreeTabCountBadge(worktreeID:terminalManager:)` leaf view — the
  per-row analogue with the same subscription isolation.
- `WorktreeRow` gained an optional `tabCountBadge: WorktreeTabCountBadge?`
  (default `nil`), rendered right after the name text, before the Spacer.
  Workspace child rows and previews are untouched (nil default).
- `WorktreeRowsView.worktreeRowView` injects the badge unconditionally for
  git-repo worktree rows; it hides itself at count 0. (Initially gated on
  `repository.worktrees.count >= 2`; the gate was removed post-review when
  badges became exclusive per level — see plan Amendments.)

## Post-review follow-ups (2026-07-25)

- **Badges exclusive per level:** collapsed git repo → aggregate count on the
  header; expanded → header badge hidden, every worktree row shows its own
  count. Workspaces keep the header badge when expanded; plain folders never
  expand. (`RepositorySectionView` gates `RepoHeaderTabCountBadge` on
  `!(isExpanded && supportsWorktrees)`.)
- **Badge compression fix:** `TabCountBadge` gained `.fixedSize()` — the
  name text's `layoutPriority(1)` otherwise squeezed the capsule below its
  natural size next to long branch names.
- **Expand Active glyph:** `chevron.right.2` replaced the chevron+dot combo
  (see above). The e2e verification section below predates this swap and the
  badge-exclusivity change; the recorded cycle behavior is unchanged.

## Tests

`RepositorySectionViewTests` (all 14 pass):

- existing `sidebarHeaderActionCollapsesWhenAnyExpandableRepositoryIsOpen`
  extended with `activeRepositoryIDs: []` (verifies the empty-active-set
  degradation keeps today's two-state behavior).
- new `sidebarHeaderActionCyclesThroughExpandActive` — full decision table:
  collapsed→expandActive, ==active→expandAll, full→collapseAll,
  mixed→collapseAll, active==all degradation both ways.
- new `activeRepositoryIDsIncludesOnlyExpandableReposWithOpenTabs` —
  terminal-manager fixture; plain folder with tabs excluded (not expandable).

## End-to-end verification (self-verify-prowl, 2026-07-25)

Debug instance on `/tmp/prowl-self-verify.sock`, driven via `prowl` CLI +
AX presses (`AXUIElementPerformAction`), single-window screenshots:

1. Repo with 3 worktrees (Kingfisher) + CLI-opened tab on main: worktree row
   shows its own "1" badge; sibling worktrees with 0 tabs show nothing;
   single-worktree repo (Prowl) shows no row badge. Header badges correct
   (Kingfisher 1, Prowl 1, relay 2).
2. Full cycle: Collapse All → all collapsed, button becomes chevron+dot
   (Expand Active, correct AX help) → press → exactly the repos with open
   tabs expand → button becomes Expand All → press → everything expands →
   button returns to Collapse All.
3. Buttons expose correct AX descriptions/help ("Collapse All",
   "Expand repositories with open tabs", "Expand All").

Note: one stale-render observation on the first debug session (header badge
not appearing for a CLI-created tab) did not reproduce after relaunch;
probe logging confirmed the header badge body re-evaluates with the correct
count on tab creation. Pre-existing rendering territory, not introduced by
this change.

`make check` clean; app + tests build clean (0 warnings).

## Docs

`docs/components/repositories-and-worktrees.md` — "Pinning & ordering"
section documents the three-state cycle and both badge levels.
