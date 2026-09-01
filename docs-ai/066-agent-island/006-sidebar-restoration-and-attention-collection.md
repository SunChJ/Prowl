# 066.006 — Sidebar Restoration and Attention Collection

## Context

The first isolation pass restored the shared icon styling but left two earlier Agent Island
changes in the existing Active Agents panel: rows still rendered a lower-right status badge, and
the original Working/status treatment had been replaced. This violated the intended boundary that
Agent Island may project roster data without redesigning the source panel.

The strong attention surface also rendered only the highest-priority entry and collapsed every
other Blocked or unviewed Done entry into `+N`. The result was a large single card rather than a
useful multi-Agent selection surface.

## Change

- Restore `ActiveAgentRow`, `ActiveAgentsPanel`, `SidebarActiveAgentsOverlay`, and the related
  `SidebarListView` helpers to their pre-Agent-Island implementation.
- Remove the shared status-badge icon component introduced by Agent Island. Sidebar runtime icons,
  the Bagua Working indicator, status text, context menus, and row behavior remain unchanged.
- Keep roster rendering helpers used by the secondary island inside Agent Island-owned files.
- Replace the single strong attention card plus `+N` with an actual collection of individually
  actionable Agent cells.
- Use one compact column for a single attention entry and two columns for multiple entries. Show
  up to three rows before enabling vertical scrolling.
- Each cell presents the runtime icon and Agent name with the same `Blocked` or `Done` label used
  by Active Agents at the lower leading edge. The repository and the same branch/tab subtitle used
  by the expanded roster occupy two trailing lines. No lower-right badge is added to the runtime icon.
- Measure the secondary roster's real row content instead of multiplying by a generous fixed row
  height. Keep the viewport content-sized up to `360pt`, then enable scrolling at that maximum.
- Keep Blocked-before-Done ordering from `ActiveAgentsFeature.islandAttentionEntries`; clicking any
  cell continues through the existing island focus action.
- Keep status-ring animation, Reduce Motion behavior, reducer lifecycle semantics, navigation,
  and window placement unchanged.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)

## Verification

- `ActiveAgentRow.swift`, `ActiveAgentsPanel.swift`, `SidebarActiveAgentsOverlay.swift`, and
  `SidebarListView.swift` match the `origin/main` merge-base byte-for-byte.
- Targeted tests pass for the restored Bagua indicator, island icon projection, and attention
  collection layout across one item, multiple items, and scrolling beyond three rows.
- Roster layout tests cover exact measured height, first-layout estimation, and the `360pt`
  scrolling cap.
- `make check`, `make test`, and `make build-app` pass. The full test run reports 2,951 app tests
  plus the 2-test secondary suite with zero failures; the Debug build reports zero warnings.
- The existing Debug process was not restarted for this visual revision because it was hosting an
  active Agent session. This avoids interrupting unrelated user work; the new binary is built and
  ready for the next safe relaunch.
