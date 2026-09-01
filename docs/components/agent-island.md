# Agent Island

> A notch-aware, always-available projection of Active Agents for macOS.

**Keywords:** agent island, dynamic island, notch, floating pill, active agents, working, blocked, done, idle, display

**Related:** [active-agents](active-agents.md) · [agent-detection](agent-detection.md) · [settings](settings.md)

## What it is

Agent Island shows Prowl's existing Active Agents roster at the top of one display. It does
not detect agents or track acknowledgement separately: every label and transition comes from
the same `Working`, `Blocked`, `Done`, and `Idle` entries used by the sidebar panel.

The island is visible whenever that roster contains at least one entry. It merges into the
top edge on a notched display and uses a centered floating pill below the menu bar on other
displays. It remains available across Spaces, fullscreen applications, and Stage Manager.
On a notched display, compact content occupies equal wings beside the physical camera cutout;
the cutout itself is reserved from layout using the screen's auxiliary menu-bar areas.

## Presentation states

| Active Agents state | Island behavior |
|---|---|
| **Working** | Compact, low-priority status. The most recently changed Working agent appears immediately; multiple Working agents rotate every four seconds. Hovering or opening the roster pauses rotation. Its projected runtime icon uses a fluid rotating orange outline. |
| **Blocked** | Strong **Needs input** card below the compact island. Blocked takes priority over Done. |
| **Done** | Strong **Completed** card while the existing Active Agents entry remains unviewed. |
| **Idle** | Full details appear in the expanded roster. A projected compact icon may remain visible with a quiet static outline when higher-priority entries do not displace it. |

The compact trailing area projects only real runtime icons, keeping status presentation scoped
to Agent Island instead of changing shared Active Agents rows or attention cards. Up to three
icons appear at a larger size on restrained dark backgrounds. Idle uses a static muted outline;
Working, Blocked, and Done use continuously circulating orange, red, and blue gradient outlines.
The nearest icon is the highest-priority entry (`Blocked`, `Done`, `Working`, then `Idle`),
recency breaks ties, and larger rosters show two icons plus `+N`. This is a compact roster
projection rather than a loading animation and does not create another source of agent state.

When several entries need attention, the island shows the highest-priority, most-recent entry
and a `+N` count. These callouts cannot be dismissed independently: Blocked clears only when
the agent leaves that state, Done clears when existing seen handling changes it to Idle, and
removed Active Agents entries disappear automatically.

If no agent is Working but the roster still contains Idle, Blocked, or Done entries, the
compact island shows a neutral agent count so the roster remains reachable.

## Interactions

- Click the compact island to open or close the full roster without bringing Prowl forward.
- Click a Needs input or Completed card to bring Prowl forward and focus its exact worktree,
  tab, and pane.
- The expanded roster uses the same rows, status pills, ordering, titles, and context menus as
  the [Active Agents panel](active-agents.md). Clicking a row first restores Prowl, then uses
  the panel's existing exact-focus path.
- Click **Open Prowl** in the roster header to restore and activate the current Prowl main
  window without changing the selected agent.
- Click outside the roster or press `Esc` to collapse it. This does not mark Blocked or Done
  entries as handled.

## Display settings

Settings → Agents → Agent Island contains:

- **Show Agent Island** (`agentIslandEnabled`, default `true`).
- **Display** (`agentIslandDisplayPreference`, default Automatic).

Automatic follows the display containing Prowl's main window. With no main window screen it
prefers a built-in notched display, then the macOS main display, then the first available
display. A fixed display is stored by CoreGraphics display UUID. If it disconnects, placement
temporarily uses Automatic without erasing the choice, and returns when that UUID reconnects.

With Reduce Motion enabled, island expansion and status changes use fades instead of movement,
and projected Agent outlines retain their state colors without continuous rotation.

## Boundaries

Agent Island does not provide inline permission approval or terminal input. It also does not
invent a failure state for an interrupted process; an interruption appears only if Active
Agents already maps it to Blocked or Done.
