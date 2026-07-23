# 002.005 — Global Custom Commands: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-13 | Added global command storage, resolution, settings UI, source-qualified routing, tests, and manual documentation. | `f481db26` |
| 2026-07-19 | Extracted the repository command table into the shared `CustomCommandsEditor` and adopted it for the global list (icon picker, inline editing, shortcut recording with Replace/Cancel conflicts, explicit +/− removal). Restored the unqualified palette ID for repository commands. | PR #582 review follow-up |

## Outcome & current state (as of 2026-07-19)

- `UserGlobalSettings` persists `customCommands` in `~/.prowl/global.onevcat.json` through
  `UserGlobalSettingsKey`.
- `EffectiveCustomCommand` resolves local commands before global commands and suppresses a
  global command when a trimmed, case-insensitive local title matches.
- `AppFeature`, `WorktreeCommands`, `WorktreeDetailView`, and `CommandPaletteFeature` use
  source-qualified command identity. Local bindings retain `custom_command.<uuid>` and
  global bindings use `custom_command.global.<uuid>`; a local shortcut collision disables
  the global binding.
- Settings → Commands edits the global list. Toolbar, overflow, and menu entries
  render identically for both sources; the global origin is only surfaced in hover
  tooltips ("Defined as a global command") after onevcat rejected a visible globe marker.
- Both settings surfaces embed `CustomCommandsEditor`
  (`supacode/Features/Settings/Views/CustomCommandsEditor.swift`), parameterized by
  `CustomCommandSource` so shortcut resolution targets the right binding namespace. The
  editor owns its transient selection/popover/recording state; persistence stays with the
  host reducers (`RepositorySettingsFeature.binding`, `GlobalCustomCommandsFeature.binding`).
- Palette IDs: repository commands keep the pre-global `custom-command.<uuid>` form so
  persisted palette recency survives; global commands use `custom-command.global.<uuid>`,
  mirroring the keybinding scheme.

## Deviations from plan

None. An initial compact global editor shipped first; the follow-up replaced it with the
shared editor extraction the plan originally called for.

## Open questions

None.
