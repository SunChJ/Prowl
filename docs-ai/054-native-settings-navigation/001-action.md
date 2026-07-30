# 054 — Native Settings Navigation: Action Log

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-30 |
| **Primary PRs** | — (filled on merge) |

## Outcome

Settings is now a SwiftUI-owned singleton `Window` scene rather than a retained
AppKit `NSWindow`. Its standard macOS toolbar chrome is composed by SwiftUI:
the traffic lights sit in the sidebar field, the system sidebar toggle remains
available, and a drilled-in Agent Profile editor receives the compact native
Back control beside its title.

The Agents page now has genuine navigation instead of a conditional content
swap. The profile list is the root of a `NavigationStack`; selecting a profile
pushes its `AgentProfileEditorFeature`, and the system Back control pops the
TCA-owned `StackState` path back to the list.

## Implementation map

- `supacode/App/supacodeApp.swift` — declares
  `Window("Settings", id: WindowID.settings)` with default system toolbar
  styling and the shared app store/environment values.
- `supacode/App/SettingsWindowOpener.swift` +
  `supacode/Clients/SettingsWindow/SettingsWindowClient.swift` — bridge
  reducer-driven entry points to `openWindow(id:)`; they never retain or create
  an `NSWindow`.
- `supacode/Commands/WindowCommands.swift` and
  `SidebarFooterView.swift` — route Cmd-comma/menu and the sidebar gear through
  the SwiftUI window action. A focused-scene close action preserves Cmd-W for
  Settings when terminal close commands are active in the main scene.
- `supacode/Features/Settings/Views/SettingsView.swift` — uses the normal
  `NavigationSplitView` sidebar toggle and leaves all toolbar placement to
  SwiftUI/macOS.
- `AgentProfilesFeature` / `AgentProfilesSettingsView` — replace
  `@Presents editor` and a custom page swap with TCA `StackState`,
  `NavigationStack(path:)`, and `NavigationLink(state:)`.
- `AgentProfileEditorView` — relies on its navigation title and the system Back
  behavior; no in-page Back control or custom transition remains.

## Verification

- Targeted tests passed: `SettingsWindowOpenerTests`, `AgentProfilesFeatureTests`,
  `AgentProfileEditorFeatureTests`, `AppFeatureSettingsSelectionTests`, the
  Command Palette Settings-open case, `WindowCloseShortcutPolicyTests`, and
  `WindowSurfacingTests`.
- `make check` completed cleanly and `make build-app` completed without errors
  or warnings; the full `make test` suite also passed.
- In an isolated Debug Prowl instance, verified visually and through
  Accessibility:
  - Cmd-comma opens the singleton Settings window with native traffic lights,
    sidebar toggle, and titlebar placement.
  - Agents → Codex Default pushes the editor and shows the system Back button
    beside `Codex Default`; activating it returns to the Agents list.
  - Selecting General while the editor is visible returns to General rather
    than retaining stale Agent detail state.
  - The sidebar toggle hides and restores the sidebar.
  - Cmd-W closes Settings from both its root and a drilled-in editor; Cmd-comma
    subsequently reopens it.

## Deviation from the initial experiment

The planned special SwiftUI `Settings` scene was intentionally not shipped.
Its preference-scene chrome still produced an inset sidebar and misplaced
navigation controls in the nested split/stack combination. A standard
singleton `Window` scene is also public SwiftUI, while matching the target
macOS Settings-style layout in the actual debug app.
