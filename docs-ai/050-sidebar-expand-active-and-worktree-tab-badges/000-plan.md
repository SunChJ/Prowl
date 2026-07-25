# 050 — Sidebar: Expand-Active Third State + Per-Worktree Tab Badges: Plan

| | |
| --- | --- |
| **Status** | Implemented — see [001-action.md](001-action.md) |
| **Anchor date** | 2026-07-25 |
| **Primary PRs** | [#612](https://github.com/onevcat/Prowl/pull/612) |
| **Related** | [026 sidebar-container-refactor](../026-sidebar-container-refactor/000-plan.md), [033 ui-refresh-2026-05](../033-ui-refresh-2026-05/000-plan.md), [042 project-workspaces](../042-project-workspaces/000-plan.md) |

## Background

The sidebar's repository list header has a single toggle button that flips
between `Expand All` and `Collapse All` (`SidebarListView.repositoryListHeaderAction`:
any expandable repo expanded → offers Collapse All; none expanded → offers
Expand All). Expansion state is persisted as the *collapsed* ID set in
`@Shared(.appStorage("sidebarCollapsedRepositoryIDs"))` and derived into
`RepositoriesFeature.State.expandedRepositoryIDs`.

The open-tab count badge exists only on the repository section header
(`RepoHeaderTabCountBadge`, backed by `RepositorySectionView.openTabCount`):
for git repos it sums `tabManager.tabs.count` over all worktrees; for plain
folders and workspaces it reads the terminal state keyed by `repository.id`
(workspace child tabs all live under the workspace's own ID). The badge hides
at count 0.

Worktree rows (`WorktreeRowsView` → `WorktreeRow`) render main / pinned /
pending / unpinned sections and carry no per-worktree tab information today.

## Goals

1. **Third header-button state — "Expand Active"**: clicking the header button
   cycles through a state that expands exactly the repos/workspaces that have
   at least one open terminal tab, collapsing the rest.
2. **Per-worktree tab count badge**: inside an expanded git repo with more
   than one worktree, each worktree row shows its own open-tab count badge.
   A repo with a single worktree shows no extra UI.

### Non-goals

- Changing what "open tab" means (no agent-status coupling).
- Canvas / Shelf segments; this is the Default (tabbed) sidebar list only.

## Proposed design (pre-interview draft; open points below)

### A. Expand-Active third state

- Semantics (draft): a one-shot *repo-level* expansion action — set
  `expandedRepoIDs` to `{ repo ∈ expandable | openTabCount(repo) > 0 }`.
  Worktree rows inside expanded repos are NOT filtered; persistence flows
  through the existing collapsed-set binding like the other two actions.
- Cycle (draft): Expand All → Expand Active → Collapse All → Expand All …,
  derived from the current expansion state (button keeps showing the *next*
  action).
- Icon (draft): keep chevron family for the two existing states; third state
  needs a distinct glyph + tooltip (`Expand Active`), TBD in interview.

### B. Per-worktree tab badges

- Reuse the visual style of `RepoHeaderTabCountBadge` (caption2, monospaced
  digit, capsule quaternary background), rendered as an isolated leaf view so
  only the badge subtree subscribes to `WorktreeTerminalManager` churn
  (same isolation rationale as the repo header badge).
- Show on worktree rows only when the repo has ≥ 2 worktrees; count for a row
  is `tabManager.tabs.count` of that worktree; hide at 0 (draft).

## Open questions (interview queue)

1. ~~Third-state semantics~~ → resolved, see Decisions #1.
2. ~~Cycle order~~ → resolved, see Decisions #2.
3. ~~Third-state icon / tooltip~~ → resolved, see Decisions #3.
4. ~~No-active-tab behavior~~ → resolved, folded into Decisions #2.
5. ~~Worktree badge placement/visibility~~ → resolved, see Decisions #4.
6. ~~Workspace children / plain folders~~ → resolved, see Decisions #5.

All questions resolved on 2026-07-25; see Decisions.

## Decisions (interview record)
_Each entry supersedes the draft above._

1. **Expand Active is a repo-level one-shot action** (2026-07-25). Clicking it
   sets the expanded set to exactly the expandable repos/workspaces with
   `openTabCount > 0`; worktree rows inside expanded repos are never filtered.
   No persistent mode; persistence flows through the existing collapsed-set
   binding, and manual expand/collapse afterwards behaves as today. "只显示"
   means display-side expansion only — no side effects on tabs.
2. **Cycle: Collapsed → Expand Active → Expand All → Collapse All**
   (2026-07-25). Derivation stays a pure function of the current expansion
   state, no stored mode/cursor:
   - all collapsed → Expand Active (degrades to Expand All when the active
     set is empty or equals the full expandable set);
   - expanded == active set (non-empty, proper subset) → Expand All;
   - all expanded → Collapse All;
   - any other mixed state → Collapse All (matches today's behavior).
   Accepted cost: reaching "expand everything" from fully collapsed takes two
   clicks when an active set exists.
3. **Icon: `chevron.right` + accent dot overlay** (2026-07-25). The third
   state keeps the disclosure glyph family: `chevron.right` with a small
   (~4pt) accent-colored filled circle at the top-trailing corner (drawn as an
   overlay, not a new symbol). Three-state visuals: right+dot (Expand Active)
   → right (Expand All) → down (Collapse All). Title/tooltip: "Expand
   Active"; help text "Expand repositories with open tabs". The 45°-rotation
   idea was rejected as visually mushy; filter/bolt glyphs rejected for
   wrong or broken semantics.
4. **Worktree badge: after the name, hide at 0, all rows equal**
   (2026-07-25). Badge sits right after the worktree name (before the
   Spacer), mirroring the repo header's name→badge layout; visual style
   reuses `RepoHeaderTabCountBadge` (caption2 monospaced digits, quaternary
   capsule), implemented as an isolated leaf view so only the badge subtree
   subscribes to `WorktreeTerminalManager`. Hidden at count 0. Main worktree
   participates like any other row (no exemption). Pending rows have no
   terminal state so they hide naturally; deleting/archiving rows follow
   plain count logic. Multi-worktree gate: `repository.worktrees.count >= 2`.
5. **No per-row badge for workspace children or plain folders**
   (2026-07-25). Workspace child tabs are keyed by the workspace's own ID
   (`focusOrCreateTabInDirectory`); per-child attribution would need
   working-directory bucketing with fuzzy semantics. Plain folders have no
   child rows. Both keep only the existing header badge. Workspaces still
   participate in Expand Active via their aggregate `openTabCount`.

## Implementation sketch

- `SidebarListView.RepositoryListHeaderAction` gains `.expandActive`:
  title "Expand Active", dedicated help text ("Expand repositories with open
  tabs"), glyph = `chevron.right` (no rotation) + ~4pt accent dot overlay at
  top-trailing.
- `repositoryListHeaderAction(...)` gains an `activeRepositoryIDs` parameter
  and implements the Decisions #2 table; stays a pure static function, tests
  extended in `RepositorySectionViewTests.swift`.
- Active set = expandable repos with
  `RepositorySectionView.openTabCount(for:terminalManager:) > 0`. To avoid
  subscribing `SidebarListView.body` to `WorktreeTerminalManager` churn, the
  header button moves into an isolated leaf view that owns the
  terminalManager read (same pattern as `RepoHeaderTabCountBadge`) and
  writes the new expanded set through the existing binding
  (`expandedRepoIDs = activeIDs` for `.expandActive`).
- Worktree badge: shared capsule style extracted from
  `RepoHeaderTabCountBadge`; new leaf view (terminalManager + worktree ID)
  injected into `WorktreeRow` after the name; `WorktreeRowsView` gates it on
  `repository.worktrees.count >= 2`.

## Verification

- Unit tests for the new header-action derivation (pure function over
  expansion state + active set).
- Manual smoke: mixed repos (with/without tabs), workspace, plain folder;
  cycle through the three states; single- vs multi-worktree badge visibility.
- `make check`, `make build-app`.

## Amendments

- 2026-07-25 (post-PR review by onevcat): **badges are exclusive per level,
  not duplicated.** Showing `repo 5 / main 2 / other 3` simultaneously reads
  as redundant. Revised rule supersedes Decisions #4's multi-worktree gate:
  - git repo **collapsed** → header shows the aggregate count;
  - git repo **expanded** → header badge hidden, every worktree row shows its
    own count (single-worktree repos included — the `worktrees.count >= 2`
    gate is removed, unifying the code path);
  - workspaces keep the header badge even when expanded (child rows carry no
    per-row count; Decisions #5 unchanged) and plain folders never expand.
