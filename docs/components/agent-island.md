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
| **Working** | Compact, low-priority status. The most recently changed Working agent appears immediately; multiple Working agents rotate every four seconds. Title-only refreshes preserve the current item and timer. Hovering or opening the roster pauses rotation. Its projected runtime icon uses a fluid rotating orange outline. |
| **Blocked** | Compact **Blocked** cell below the compact island. Blocked entries appear before Done entries. |
| **Done** | Compact **Done** cell while the existing Active Agents entry remains unviewed. |
| **Idle** | Full details appear in the expanded roster. A projected compact icon may remain visible with a quiet static outline when higher-priority entries do not displace it. |

The compact trailing area projects only real runtime icons, keeping status presentation scoped
to Agent Island instead of changing the original Active Agents panel. Up to three
icons appear at a larger size on restrained dark backgrounds. Idle uses a static muted outline;
Working, Blocked, and Done use continuously circulating orange, red, and blue gradient outlines.
The leftmost icon is the most recently changed non-Idle entry. Other non-Idle entries follow by
recency, while Idle entries remain on the right even when their timestamp is newer. Larger
rosters keep three complete Agent icons visible and place only the remaining `+N` count at the
cluster's trailing lower edge without an outline. For example, four Agents appear as three icons
plus `+1`. This is a compact roster projection rather than a loading animation and does not create
another source of agent state.

Attention entries appear as individually actionable collection cells rather than a first-item
stack summary. A single entry uses a narrow one-column surface; multiple entries use two columns,
with up to three visible rows before vertical scrolling. Each cell retains the existing
Blocked-before-Done, then recency ordering. The Agent name and shared `Blocked` or `Done` state
appear on the left, while the same repository and branch/tab subtitle used by Active Agents appear
as two trailing lines. These callouts cannot be dismissed independently: Blocked clears only when
the agent leaves that state, Done clears when existing seen handling changes it to Idle, and removed
Active Agents entries disappear automatically.

If no agent is Working but the roster still contains Idle, Blocked, or Done entries, the
compact island shows a neutral agent count so the roster remains reachable.

## Interactions

- Click the compact island to open or close the full roster without bringing Prowl forward.
- Click a Blocked or Done cell to bring Prowl forward and focus its exact worktree,
  tab, and pane.
- The expanded roster composes the original Active Agents row and display semantics without
  changing the [Active Agents panel](active-agents.md). It retains ordering, titles, Workflow
  role badges, and the shared context menu, including **Run Workflow**. Clicking a row first
  restores Prowl, then uses the panel's existing exact-focus path. Its viewport tracks the rows'
  measured content height and caps at `360pt`, enabling scrolling only after the content exceeds
  that limit.
- Click **Open Prowl** in the roster header to restore and activate the current Prowl main
  window without changing the selected agent.
- Click outside the roster or press `Esc` to collapse it. This does not mark Blocked or Done
  entries as handled.

The secondary roster appears directly below the compact island without a custom movement, scale,
fade, or spring transition.

## Display settings

Settings → Notifications → Agent Island contains:

- **Show Agent Island** (`agentIslandEnabled`, default `false`).
- **Display** (`agentIslandDisplayPreference`, default Automatic).

Automatic follows the display containing Prowl's main window. With no main window screen it
prefers a built-in notched display, then the macOS main display, then the first available
display. A fixed display is stored by CoreGraphics display UUID. If it disconnects, placement
temporarily uses Automatic without erasing the choice, and returns when that UUID reconnects.

With Reduce Motion enabled, compact carousel changes use fades and projected Agent outlines retain
their state colors without continuous rotation. Secondary-island expansion is static for everyone.

## Boundaries

Agent Island does not provide inline permission approval or terminal input. It also does not
invent a failure state for an interrupted process; an interruption appears only if Active
Agents already maps it to Blocked or Done.
