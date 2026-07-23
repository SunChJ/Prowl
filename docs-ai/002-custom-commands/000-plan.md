# 002 — Custom Commands: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-02-27 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #101, #205 (initial wave was direct commits `76046bc0`, `b5c58e4d`, `562042fc`) |
| **Sources** | `docs-ai/017-upstream-sync-process/upstream-ledger.md` (Old Log rows for `76046bc`/`b5c58e4`/`562042f`), fork issue #85, PR descriptions #101/#205/#245/#299/#362, commit messages |
| **Related** | [012-keybinding-system](../012-keybinding-system/000-plan.md), [022-tab-title-and-icon](../022-tab-title-and-icon/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md), [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md), `docs/components/custom-actions.md` |

## Background

Upstream supacode offered exactly one on-demand per-repo command: the Run Script. onevcat
wanted repeated repo workflows (build, test, push, one-shot agent prompts) available as
first-class buttons and hotkeys next to Run — multiple named actions per repository, each
with its own icon and execution behavior. This was one of the first fork-only features
(day two of the fork), so it also had to be structured to survive continuous upstream
merges.

## Goals

- Multiple named commands per repository, each with SF Symbol icon, title, shell command,
  and execution mode.
- Two execution modes at introduction: run in a **new terminal tab** (`shellScript`) or
  type into the **focused pane** (`terminalInput`).
- Terminal-input commands must actually *execute*, not just paste: inject the text and a
  real Return key press, so shells and TUIs (agents) both treat it as Enter.
- Optional per-command keyboard shortcut that, while a repo is selected, takes precedence
  over Ghostty's key handling and app shortcuts.
- Surfaces: buttons in the worktree toolbar (after Run) and entries in the Worktrees menu.

**Non-goals** (initially): no split target, no auto-close, no palette or Canvas
integration — all of these arrived in later waves (see Amendments and the action log).

## Design / Approach

- **Model**: `OnevcatCustomCommand` (title / `systemImage` / `command` /
  `OnevcatCustomCommandExecution` / optional `OnevcatCustomShortcut`) inside
  `OnevcatRepositorySettings`, capped at 3 commands (`maxCustomCommands`). All types
  carried an `Onevcat` prefix and lived in fork-added files, deliberately isolating the
  feature from upstream-owned code to keep merges clean. (The prefix was later renamed to
  `User*` on 2026-03-27, PR #79 era; see
  [012-keybinding-system](../012-keybinding-system/000-plan.md).)
- **Storage**: a repo-scoped JSON file separate from upstream's settings
  (`supacode.onevcat.json` at the repo root at the time; moved to
  `~/.prowl/repo/<repo-last-path>/` and renamed `prowl.onevcat.json` during the rebrand —
  see [004-prowl-rebrand](../004-prowl-rebrand/000-plan.md)).
- **Execution**: `AppFeature` action dispatches through `TerminalClient` —
  `createTabWithInput` for the new-tab mode, `insertText` for terminal-input mode.
- **Terminal-input Return injection**: `GhosttySurfaceView.submitLine()` synthesizes a
  `\r` keyDown/keyUp `NSEvent` pair (keyCode 36) through the normal key path instead of
  appending `\n` to the injected text (commit `562042fc`).
- **Shortcut precedence**: a process-global `OnevcatCustomShortcutRegistry` records the
  active repo's custom shortcuts so `GhosttySurfaceView.performKeyEquivalent` can let a
  matching key combo bypass Ghostty and reach the SwiftUI `.keyboardShortcut` handlers.

## Alternatives & decisions

- **Fork-isolation over upstream integration**: prefixed types, fork-added files, and a
  separate per-repo settings file were chosen so the feature adds few edit points in
  upstream-owned files. The old change-list per-commit table marks all three initial
  commits "Fork only".
- **Synthesized Return key over `\n` in text** (commit `562042fc`): text injection alone
  left the command sitting unexecuted at the prompt in some programs; a synthesized key
  event goes through the same path as a physical Enter.
- **3-command cap at introduction**: kept the toolbar bounded; removed a month later once
  an overflow menu existed (#101, see amendment 002).

## Amendments

- Updated 2026-03-31: UI revamp — table + detail editor, 3-command cap removed, toolbar
  overflow menu, shortcut recording unified with the keybinding system (#101, fork issue
  #85) — see [002-ui-revamp-and-keybinding-unification.md](002-ui-revamp-and-keybinding-unification.md)
- Updated 2026-04-17: New Split execution target + per-command Close on success (#205) —
  see [003-split-target-and-close-on-success.md](003-split-target-and-close-on-success.md)
- Updated 2026-07-13: Global commands extend the repository-scoped model with local-title
  precedence, source-qualified identities, and shared settings storage — see
  [004-global-custom-commands.md](004-global-custom-commands.md)
- Updated 2026-07-19: Visibility gates, source ordering, and per-repository Global command
  controls — see [006-visibility-gates-and-scope-ordering.md](006-visibility-gates-and-scope-ordering.md)
