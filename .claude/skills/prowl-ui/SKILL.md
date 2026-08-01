---
name: prowl-ui
description: Explicitly inspect and operate the native Prowl Debug UI with agent-ctrl on macOS. Use only when the user asks to verify or drive Prowl UI behavior, especially Settings, sheets, menus, popovers, view switching, repository selection, and Active Agents. Do not invoke automatically after implementation, and use prowl-cli instead for tabs, panes, terminal content, command routing, or agent sessions.
---

# Prowl UI

## Scope

Use `agent-ctrl` as the semantic macOS UI surface for an exact Prowl Debug process. Keep the workflow exploratory: choose
the shortest interaction that proves the declared behavior, while applying the Prowl-specific constraints below.

This skill is explicit-only. Do not run it merely because Prowl code changed. When called from `self-verify-prowl`, run the
preflight before loading this file so a missing tool or permission becomes a cheap `SKIPPED` result.

Split responsibility by surface:

- Use `prowl-cli` for repositories and worktrees as data, tabs, panes, terminal input and output, task state, and agent
  sessions. Read its skill before writing commands.
- Use `agent-ctrl` for native windows, Settings, sheets, menus, popovers, sidebar disclosure, and other AppKit or SwiftUI
  controls.
- Use a PID-scoped screenshot only for visual assertions such as selection appearance, geometry, clipping, or hierarchy.

Do not use Accessibility to type into Ghostty terminal surfaces or infer terminal state from pixels.

## Preflight Without Prompting

Run the bundled script before opening an AX session:

```bash
.claude/skills/prowl-ui/scripts/preflight.sh
```

It checks `command -v agent-ctrl`, requires version 0.1.3 or newer, inspects `info --json`, and runs
`doctor --json --quick`. Its contract is:

- Exit `0` with `{"status":"READY",...}` when the macOS AX surface and Accessibility permission are ready.
- Exit `2` with `{"status":"SKIPPED",...}` when the binary, compatible version, JSON parser, AX surface, or permission is
  unavailable.

On `SKIPPED`, stop this UI scenario immediately. Do not install the tool, open System Settings, or enter an LLM-driven UI
loop. Installation is a separate user-authorized action.

## Pin the Debug Process

Never target Prowl by process name or appearance. The installed and Debug apps are both named `ProwlApp` and share user
data. When using this skill with `self-verify-prowl`, source its helpers and resolve the DerivedData Debug PID:

```bash
. .claude/skills/self-verify-prowl/scripts/helpers.sh
pid="$(debug_pid_with_window)"
test -n "$pid"

session="prowl-ui-$$"
agent-ctrl open ax --session "$session"
agent-ctrl snapshot --target-pid "$pid" --session "$session"
```

Keep one session for one scenario and always close it:

```bash
agent-ctrl close --session "$session"
```

Window IDs and element refs are ephemeral. Re-run `window-list` or a PID-scoped snapshot after opening or closing a
window. Do not assume `window:0`, `@e0`, or any previous ref still identifies the same object.

## Observe, Act, Re-observe

For every action:

1. Take a fresh snapshot pinned to the Debug PID or its already-discovered window.
2. Resolve the narrowest semantic target with `find`, or inspect the tree when the useful target is a parent cell.
3. Perform exactly one action.
4. Wait for a concrete result or disappearance when possible.
5. Take another snapshot and assert the resulting label, role, state, value, title, or CLI state.

Typical commands use this argument order:

```bash
ref="$(agent-ctrl find "Canvas" --role button --exact --first --session "$session")"
agent-ctrl click "$ref" --session "$session"
agent-ctrl wait-for "Arrange" --role button --session "$session"
agent-ctrl snapshot --session "$session"
arrange_ref="$(agent-ctrl find "Arrange" --role button --exact --first --session "$session")"
agent-ctrl get name "$arrange_ref" --session "$session"
```

An action response such as `ok method=ax-press`, `ax-value`, or `cg-event` is delivery telemetry, not evidence that Prowl
changed state. Never report `PASS` from the action response alone. If delivery is uncertain, observe before considering a
retry.

Use refs only from the latest snapshot. `find` searches the cached snapshot; it does not walk the UI itself. For negative
scroll deltas, terminate option parsing explicitly, for example:

```bash
agent-ctrl scroll --ref "$ref" --session "$session" -- 0 -600
```

## Prowl Main Window Knowledge

### View Modes

The top-level `Default`, `Canvas`, and `Shelf` controls are buttons. `Canvas` has distinctive semantic descendants such as
`Canvas navigation help`, `Arrange`, `Organize`, and `Tile`, so assert those after switching.

SwiftUI currently does not expose a selected AX state for `Default` or `Shelf`. Their button press and visual highlight are
not enough for a semantic `PASS`. Prove a mode through distinctive content or behavior when available; otherwise declare a
visual assertion and use a pinned screenshot, or report the semantic assertion as `INCONCLUSIVE`.

### Active Agents

Collapse and expansion are reliably observable through the footer control:

- Expanded state exposes `Hide Active Agents`.
- Collapsed state exposes `Show Active Agents`.

Assert the label flip after each click. Do not infer collapse solely from the continued presence or absence of the
`Active Agents` region.

### Repository and Worktree Selection

Repository and worktree text regions can return a successful AX press without changing selection. After a selection
attempt, query the dedicated Debug socket with `prowl list --json` and compare the focused worktree or pane.

If semantic delivery did not change the CLI state:

1. Re-snapshot and prefer the containing row or cell over its text region when one exists.
2. Check the target bounds against the root window bounds. Nodes below or above the viewport may still claim
   `visible=true`.
3. If the row is on-screen and has no actionable semantic parent, use one physical click at the center of its fresh bounds.
4. Query `prowl list --json` again. Do not repeat the click if the result is still ambiguous.

Never hardcode repository names, worktree labels, refs, or screen coordinates.

### Toolbar, Popovers, and Menus

The Agents toolbar menu has accessibility identifier `agents-toolbar-menu`; the adjacent quick-launch control uses
`agents-toolbar-quick-launch`. Opening Agents produces a nested dialog with `Manage Agent Profiles…`; it may not appear as
a sibling in `window-list`. Do not activate a profile merely to test the popover.

Menus can appear more than once in the AX tree even though only one menu is visible. Treat duplicate menu-item nodes as one
surface. Close a menu with its toggle when that changes state; otherwise use one safe outside click and verify the expected
menu item is gone.

## Prowl Settings Knowledge

Settings uses a SwiftUI `List(selection:)` exposed as `tree "Sidebar"`. Each navigation item is typically shaped like:

```text
cell
  region "Notifications"
```

Click the `cell`, not the named text or region. `find "Notifications"` usually returns the region, so inspect its parent in
the fresh snapshot and click that cell ref. The cell action may legitimately fall back from AXPress to a physical event.

After navigation, assert both the selected row and a detail-specific heading or window title. Important title differences
include:

- The `Commands` row opens a window titled `Global Commands`.
- Repository rows open repository-specific settings whose headings include `Display`, `Worktree`, `Agents`, and scripts.

Repository rows can be present in the AX tree while outside the window. Before clicking one, compare its bounds to the
Settings window, scroll over a currently visible sidebar cell, then re-snapshot. Use a bounded scroll, observe its direction,
and adjust once rather than assuming `visible=true` or trusting a scroll success response.

Opening Settings can reorder or replace the session's top-level window IDs, and `AXRaise` may be unsupported even when the
correct window is already readable. Re-discover the window, verify its title and PID, and continue from the snapshot instead
of treating a focus failure as proof that the window is inaccessible.

## Sheets and Editable Controls

`Add...` opens the in-window `Add to Prowl` dialog. `Browse…` opens an `NSOpenPanel` sheet that remains embedded in the
main window's AX tree; it may not appear as another entry in `window-list`. Inspect the pinned tree for `dialog`, `Cancel`,
and `Open` before searching for a sibling window.

Prefer `fill` on a fresh editable ref for safe text-entry checks. Keyboard `press` can fail with `AXRaise` on sheets or
Settings. Native search fields can temporarily replace the snapshot root with a suggestions menu and may never become
structurally stable, so wait for a concrete control or value instead of relying on `wait-for --stable`.

Never add a repository, clone, launch an agent profile, archive a worktree, run a command, or persist a setting unless the
scenario explicitly requires that mutation and defines cleanup. Opening and cancelling a surface is sufficient for generic
control verification.

## Evidence and Outcome

Prefer direct semantic evidence: a fresh tree fragment, a field value, a window title, or matching `prowl` JSON before and
after. Use `agent-ctrl screenshot --session "$session"` only when pixels are part of the declared assertion.

Classify each scenario as `PASS`, `FAIL`, `SKIPPED`, or `INCONCLUSIVE`. Include the exact Debug PID, agent-ctrl version,
assertions and evidence, any physical fallback, restored state, and session cleanup. A partial semantic surface must reduce
confidence; it must not silently become a visual pass.
