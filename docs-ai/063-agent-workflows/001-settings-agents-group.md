# 063.001 — Settings Agents Group (C0)

## Context

Release R1 starts by establishing the Settings information architecture that later workflow UI will extend. The existing Agent Profiles page was a standalone “Agents” sidebar item, while the `prowl` installation controls lived under Advanced.

## Change

- Settings now has an `Agents` sidebar group with `Profiles` and `Command Line Tool` pages.
- The existing profile list is titled `Profiles`; `openAgentProfilesSettings` and “Manage Agent Profiles…” continue to select it.
- The Command Line Tool page owns the existing install/status controls and also exposes the active Unix socket path and the existing agent-help prompt.
- Advanced now contains only analytics, crash reporting, and terminal-layout controls.
- The Workflows page remains absent until 063-D1, as planned.

## Current state

The selection boundary is represented by `SettingsSection.profiles` and `.commandLineTool`. Profile editor state is initialized only for the Profiles page and is cleared when another page is selected. CLI installation behavior remains owned by `SettingsFeature`; C0 only moves its Settings presentation.

## Verification

- Focused Settings selection and CLI-install suites: 11 tests passed.
- `make check` passed.
- `make test` verified 2,366 tests with zero failures; five dependency-scan warnings remain pre-existing.
- `make build-app` passed with zero warnings and errors.
- An isolated Debug app was navigated through Settings to Profiles and Command Line Tool; both rendered with the expected native window titles and ordering.

## Refs

- Slice: 063-C0
- Branch: `feat/settings-agents-group`
