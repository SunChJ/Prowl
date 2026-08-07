# 058 — Unified Toolbar Layout: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-07 | Removed the persistent branch/folder/workspace toolbar title and hid the visible Canvas title | — |
| 2026-08-07 | Unified Normal, Shelf, and Canvas around one leading Agents + Quick Launch cluster followed by a separately surfaced notifications capsule | — |
| 2026-08-07 | Moved Rename Branch to the worktree row context menu and app-level sheet while retaining the command/shortcut path | — |
| 2026-08-07 | Made Hand Off resolve the focused Canvas card through the shared action-target resolver; added a reducer regression test | — |
| 2026-08-07 | Updated user documentation and corrected superseded toolbar references in earlier `docs-ai` entries | — |

## Outcome & current state (as of 2026-08-07)

- `supacode/Features/Repositories/Views/WorktreeDetailView.swift` always applies
  `.toolbar(removing: .title)`, preserving `WindowTitle.compute(...)` for window identity
  without rendering a toolbar title. `AgentNotificationsToolbarContent` is the shared
  leading composition for all three view modes.
- Agents and Quick Launch remain a native shared-glass group. The bell follows in a
  separate `.navigation` item with `.sharedBackgroundVisibility(.hidden)` so it keeps the
  visual gap that previously separated Agents from the branch title.
- `supacode/Features/Repositories/Views/ToolbarNotificationsPopoverButton.swift` adds the
  `standaloneNavigation` style, which draws an interactive glass capsule with metrics
  aligned to the leading Agents control. Notification count, hover, click, and read-state
  behavior are unchanged.
- Canvas assembles its Agents capsule and profile launcher from the focused Canvas
  worktree. Switching the focused card updates the leading controls without introducing a
  Canvas-specific copy of their layout.
- The former title-only implementation and tests were removed. Branch names continue to
  appear in the sidebar and terminal/agent-owned context, where they remain useful without
  consuming permanent toolbar width.
- `supacode/Features/Repositories/Views/RenameBranchPromptView.swift` retains the rename
  form. `supacode/App/ContentView.swift` presents it as a sheet from
  `PendingRenameBranchRequest`; `supacode/Features/Repositories/Views/WorktreeRowsView.swift`
  adds **Rename Branch…** to single-worktree context menus. The Worktrees menu now owns
  the configurable rename shortcut previously registered by the title button.
- `supacode/Features/App/Reducer/AppFeature+Handoff.swift` now uses the existing
  Canvas-aware `actionTargetWorktree` resolver. The Canvas Agents button therefore opens
  Hand Off for the focused card rather than silently no-oping when sidebar selection is
  `.canvas`.
- Current user behavior is documented in `docs/components/notifications.md`,
  `docs/components/handoff.md`, and `docs/components/repositories-and-worktrees.md`.

## Verification

- TDD regression: `openHandoffHudUsesCanvasFocusedWorktree()` failed before the resolver
  change and passed afterward.
- Targeted `xcodebuild test`: four Hand Off / Rename tests passed with zero failures.
- `make check`: changed-file formatting, strict `swift-format` lint, and SwiftLint passed.
- `make build-app`: Debug build passed with zero errors and zero warnings.
- Live Debug app inspection:
  - Normal: no branch item; Agents + Quick Launch and Bell render as separate capsules.
  - Canvas: no visible `Canvas` title; the same leading controls render against the
    focused-card toolbar.
  - Shelf: the same leading order and separation are retained.
  - The tested window width kept editor, run, custom-command, and update controls visible
    without branch-name pressure.

## Deviations from plan

- The initial shared-layout implementation placed Bell inside the Agents shared-glass
  group. During live review, the desired separation was clarified: Bell now uses a
  standalone glass capsule with the same gap as the removed branch item.
- Removing the toolbar anchor required the rename form to move from a popover to an
  app-level sheet. The form and reducer request model remain intact.
- Adding Agents to Canvas exposed that Hand Off still resolved only
  `selectedTerminalWorktree`; the implementation expanded to align that reducer path with
  the existing Canvas-aware action resolver and added regression coverage.

## Open questions

- None.
