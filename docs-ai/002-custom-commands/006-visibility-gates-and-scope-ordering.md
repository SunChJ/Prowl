# 002.006 — Command Visibility Gates and Scope Ordering: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-19 |
| **Primary PRs** | #600 |
| **Related** | [002 Custom Commands](000-plan.md), [012 Keybinding System](../012-keybinding-system/000-plan.md), `docs/components/custom-actions.md` |

## Background

Global commands currently appear in every repository unless a local command has a matching
trimmed, case-insensitive title. Neither scope can disable a command without deleting it, and
repository settings cannot show the effective command list that drives the toolbar.

## Goals

- Preserve commands, ordering, and shortcuts while allowing them to be disabled.
- Show both local and global commands, even when their titles match.
- Keep effective toolbar order deterministic: repository commands followed by global commands.
- Let each repository opt out of an enabled global command without editing its global definition.
- Remove disabled commands from every launch surface and shortcut dispatch.

## Design / Approach

- Add an `isEnabled` flag to `UserCustomCommand`, defaulting to `true` for legacy settings.
- Store only each repository's explicitly disabled global command IDs; an absent ID means enabled.
- Resolve both sources in repository-first order. A global command is effective only when its own
  `isEnabled` flag and its repository gate are both enabled; a local command has one gate.
- Build the app's toolbar, Worktrees menu, command palette, execution lookup, and keybinding
  registration from the effective list. Keep disabled commands and shortcuts persisted so
  re-enabling restores them.
- Extend the shared settings table with an Enabled column and explicit drag handle. The global
  editor owns global edits and reordering. Repository settings combine local and global rows:
  local rows remain editable and reorderable; global rows show a Global marker and expose only
  their This Repo gate. A globally disabled row remains configurable and says Disabled globally.
- Preserve existing local-over-global shortcut conflict precedence.

## Alternatives & decisions

- **Both matching titles remain visible**: title matching no longer suppresses global commands;
  source-qualified IDs make this safe.
- **Repository-first grouping instead of cross-scope ordering**: each scope owns its own stable
  order and drag interaction, avoiding a fragile per-repository ordering overlay for global IDs.
- **Persist only global opt-outs**: default-on global commands retain their expected all-repository
  behavior without serializing redundant `true` values.
- **One visible repository gate for Global rows**: the row reports a disabled global gate separately
  rather than conflating it with This Repo state.

## Verification

- Targeted Swift Testing passed: 42 tests across effective command resolution, repository
  persistence/reducer behavior, app command loading, keybindings, and global command settings.
- `make check` passed (`swift-format` and SwiftLint), and `make build-app` completed without
  warnings or errors.
- An isolated Debug app launched on `PROWL_CLI_SOCKET=/tmp/prowl-self-verify.sock`; the repo CLI
  listed its worktrees, created a temporary tab, and opened the target worktree. Terminal capture
  timed out without shell integration and the window capture was unavailable, so this record makes
  no visual-interaction claim beyond the compiled UI and automated coverage.

## Outcome

- `UserCustomCommand.isEnabled` defaults to `true` when old settings files omit it.
- `UserRepositorySettings.disabledGlobalCommandIDs` stores only Global opt-outs; absence remains
  enabled for a repository.
- `EffectiveCustomCommand.resolve` now filters disabled commands, preserves source-qualified IDs,
  retains duplicate titles, and orders repository commands before Global commands.
- The shared editor presents compact standard checkboxes and drag handles. It accepts only known
  local-command drag payloads, supports an unconditional append drop target, and appends read-only
  Global rows with a Global marker and This Repo gate; a globally disabled row stays configurable.
- The manual documents visibility, ordering, duplicate titles, gates, shortcut behavior, and the
  updated settings entry points.


## Amendments

### 2026-07-19 — Review follow-up

- **No same-title migration**: the clean cutover remains intentional. A one-time opt-out would
  incorrectly keep a Global command hidden after its matching local command is later deleted; the
  release note instead calls out that both commands now appear.
- **No eager dead-ID cleanup**: repository settings cannot validate Global IDs in isolation.
  Deleting a Global command therefore leaves harmless historical opt-outs rather than triggering
  cross-repository writes.
- **Settings refinements**: the trailing reorder target is always available, drop destinations
  reject unknown IDs, enable controls use compact standard checkboxes, and Global opt-outs encode
  in sorted order to avoid configuration churn.
