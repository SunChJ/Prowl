# Agent Island

> An opt-in, notch-aware projection of Active Agents at the top of one display.

**Keywords:** agent island, dynamic island, notch, floating pill, active agents, working, blocked, done, idle, display

**Related:** [active-agents](active-agents.md) · [agent-detection](agent-detection.md) · [notifications](notifications.md) · [settings](settings.md)

## What it is

Agent Island shows Prowl's Active Agents roster at the top of one display, so a blocked or
finished agent is visible while another application is in front. It does not detect agents or
track acknowledgement on its own: every label and transition comes from the same `Working`,
`Blocked`, `Done`, and `Idle` entries the sidebar panel shows.

The island is off by default. When enabled it appears whenever the roster has at least one
entry. On a notched display it merges with the top edge, with content in two wings on either side
of the camera cutout; on other displays it is a centered floating pill below the menu bar. It
stays visible across Spaces and over fullscreen applications and never becomes the active window.

## Presentation

| Active Agents state | Island behavior |
|---|---|
| **Working** | Compact, low-priority. The bar shows the most recently changed Working agent; with several, it rotates every four seconds and pauses while hovered or expanded. |
| **Blocked** | A **Blocked** cell below the bar. Blocked cells sort before Done. |
| **Done** | A **Done** cell while the entry is still unviewed in Active Agents. |
| **Idle** | Listed in the expanded roster; may also appear as a quiet icon in the compact cluster. |

The trailing edge of the bar shows up to three runtime icons: non-Idle agents first by recency,
Idle agents last, and a small `+N` for the rest. Idle icons have a static outline; Working,
Blocked, and Done icons have a rotating orange, red, or blue ring. When no agent is Working, the
bar shows a neutral agent count instead of a name.

Blocked and Done cells form a small grid under the bar: one column for a single entry, two
columns otherwise, and up to three rows before it scrolls. Each cell shows the agent name and
state on the left and the repository plus the same branch/tab subtitle as Active Agents on the
right; a live Workflow role badge takes the subtitle position, as in the sidebar. Cells cannot be
dismissed from the island. A Blocked cell clears when the agent leaves that state, a Done cell
clears once the entry is viewed, and a removed entry disappears with the roster.

## Interactions

- **Click the bar** to open or close the full roster. This does not bring Prowl forward.
- **Click a Blocked or Done cell** to bring Prowl forward and focus that agent's exact worktree,
  tab, and pane.
- **The roster** lists every entry with the same rows, ordering, Workflow badges, and context menu
  as the [Active Agents panel](active-agents.md), including **Hand Off…** and **Run Workflow**.
  Clicking a row, or choosing one of those actions, brings Prowl forward first and then behaves
  exactly as it does in the sidebar. The roster grows with its content up to `360pt`, then
  scrolls.
- **Open Prowl** in the roster header brings the main window forward without changing the
  selected agent.
- **Click outside or press `Esc`** to collapse the roster, including while another application is
  active. Collapsing never marks an entry as handled.

## Settings

Settings → Notifications → **Agent Island**:

- **Show Agent Island** (`agentIslandEnabled`, default `false`).
- **Display** (`agentIslandDisplayPreference`, default Automatic). Automatic follows the display
  that contains Prowl's main window, then a built-in notched display, then the macOS main display.
  A specific display is remembered by its hardware identifier, so it survives renames and system
  language changes; while it is disconnected the island temporarily follows Automatic and the
  picker keeps the choice under its last-known name.

With Reduce Motion enabled, carousel changes fade instead of sliding and the state rings keep
their color without rotating.

## Boundaries

Agent Island offers no inline permission approval or terminal input; it navigates to the pane
instead. It adds no failure state of its own: an interrupted agent shows up only as whatever
Active Agents already reports.
