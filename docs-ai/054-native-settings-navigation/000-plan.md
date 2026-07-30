# 054 — Native Settings Navigation: Plan

| | |
| --- | --- |
| **Status** | Implemented (see [001-action.md](001-action.md)) |
| **Anchor date** | 2026-07-30 |
| **Primary PRs** | — (filled on merge) |
| **Related** | [036 window-management-hardening](../036-window-management-hardening/000-plan.md), [053 agent-profiles](../053-agent-profiles/000-plan.md) |

## Background

Prowl's Settings window was created and retained by
`SettingsWindowManager`. It owned an `NSWindow`, titlebar appearance,
activation, closing, and a local Cmd-W monitor. The Agents editor was a
conditional detail-content swap with custom transitions and an in-page Back
button.

That architecture made a core macOS surface look bespoke. The initial SwiftUI
`Settings`-scene experiment also retained a preference-style titlebar that did
not compose correctly with the split view: its traffic lights, sidebar toggle,
and drill-in Back control were not arranged like a regular macOS Settings
window. The target is instead a SwiftUI-managed singleton window with native
split-view and navigation chrome.

## Goals

- Use a SwiftUI-owned singleton `Window` scene for Settings; no Settings-owned
  `NSWindow`, event monitor, custom titlebar, or manual Back button.
- Keep top-level sections in `NavigationSplitView`, with a persistent sidebar
  and the expected traffic-light/titlebar layout.
- Push Agent Profile editing with a real `NavigationStack`, giving macOS its
  standard compact Back control and title placement.
- Keep navigation state in TCA, including a deterministic reset when the user
  changes a sidebar section while an editor is pushed.
- Preserve every opening path: Cmd-comma/app menu, sidebar footer, Command
  Palette, repository settings, and Manage Agent Profiles.

### Non-goals

- Redesigning individual Settings forms, profile fields, or persistence.
- Changing the main-window reopening or terminal-window management paths.
- Building custom replicas of the macOS titlebar or Back button.

## Design

### Singleton SwiftUI window

`SupacodeApp` declares `Window("Settings", id: WindowID.settings)`, which is
SwiftUI's singleton auxiliary-window scene. `openWindow(id:)` presents or
brings that same window forward; it replaces the manager's retained
`NSWindow`.

`SettingsWindowOpener` is a narrow bridge for reducer-driven entry points that
do not have a `View` environment. It stores only SwiftUI's
`OpenWindowAction`; `SettingsWindowClient` remains the TCA dependency boundary.
The reducer sends `SettingsFeature.Action.setSelection` before requesting the
window, so direct entries retain their intended section. Local view entries use
the environment's `openWindow` action directly.

The standard window toolbar remains `.automatic`. This deliberately leaves
traffic lights, navigation title, and Back placement to macOS instead of
arranging any of them manually. The sidebar column uses SwiftUI's documented
`.toolbar(removing: .sidebarToggle)` and a narrow AppKit fallback removes that
same system item only when macOS 26 leaves it present in a standalone `Window`
scene. The navigation and layout remain SwiftUI-owned. A focused-scene close
action lets the shared Close Window command use SwiftUI's `dismiss` for
Settings, so Cmd-W continues to work even when the main-window terminal close
actions are currently registered.

### TCA-backed profile drill-in

`SettingsView` owns the top-level `NavigationSplitView` selection. Selecting a
non-Agent section clears `SettingsFeature.agentProfiles`, which destroys any
active drill-in state rather than leaving a stale profile editor visible.

`AgentProfilesFeature.State.path` is `StackState<AgentProfileEditorFeature.State>`.
`AgentProfilesSettingsView` binds it to `NavigationStack(path:)` and uses
`NavigationLink(state:)` for profile rows. `StackAction` writes system Back
pops directly into the reducer-owned route. Add Profile appends a destination;
editor delegates update or remove the matching profile in the parent state.

## Alternatives and decisions

| Alternative | Decision |
| --- | --- |
| Retain `SettingsWindowManager` and improve its titlebar | Rejected. It keeps the lifecycle and chrome outside SwiftUI. |
| Use SwiftUI's special `Settings` scene | Rejected after a visual prototype. Its preference-scene chrome did not yield the desired split-window placement for traffic lights, sidebar toggle, and nested Back navigation. |
| Direct `navigationDestination` in the split detail column | Rejected. It replaces the detail root rather than creating the desired push/back hierarchy. |
| Conditional editor-content swap and custom Back | Rejected. It imitates navigation but cannot integrate with native window navigation controls. |
| Wrap the entire split view in one stack | Rejected. Top-level sidebar selection must remain available while the detail column drills in. |

## Acceptance gates

- Root Settings window visually uses the standard macOS window chrome.
- Agents → profile uses the system-provided Back control beside the navigation
  title; Back returns to the profile list.
- The sidebar remains visible and selectable during an editor drill-in; choosing
  another section shows that section's root content.
- Cmd-comma opens/re-surfaces the one Settings window, and Cmd-W closes it.
- Targeted TCA tests cover route push/pop, mutations through the path, and
  sidebar-reset behavior; the app builds and manual debug-window verification
  captures the root, Agents, editor, persistent sidebar, and close/reopen
  paths.
