# 066.010 — Nonactivating Interaction and Display Refresh

## Context

A second review of PR #753 found four gaps that unit and build validation did not expose:

- a nonactivating panel cannot receive `Esc` while another application remains active;
- shared Handoff and Workflow menu actions could create Prowl-owned UI without surfacing the
  closed, minimized, or inactive main window;
- Blocked/Done attention cells omitted the Workflow role badge already shown by Active Agents and
  the expanded island roster;
- screen-parameter observers independently refreshed the display catalog and panel placement, so
  notification ordering could leave placement based on a stale screen list.

## Change

- Keep `AgentIslandPanel` non-key and non-main. While the roster is expanded, poll the combined
  session Escape-key state at a low fixed frequency and collapse only on a key-down edge. This
  avoids Accessibility/Input Monitoring permissions and preserves Ghostty focus isolation.
- Route island-originated Handoff and Run Workflow selections through explicit island actions.
  Surface the singleton Prowl main window first, then dispatch the unchanged shared Active Agents
  action so focus, HUD, and Workflow behavior remain single-sourced.
- Restart the carousel after an island row or header action collapses the roster, because expanded
  state is a material timer suspension condition.
- Pass live Workflow badges into the attention-cell presentation resolver, matching the sidebar
  and expanded roster subtitle.
- Refresh `AgentIslandDisplayCatalog` synchronously inside the controller's screen-parameters
  handler before resolving the next panel frame.
- Cover Escape edge detection, island context routing, surface-first forwarding, and attention
  Workflow presentation with focused tests.

## Refs

- [Agent Island plan](000-plan.md)
- [Agent Island action log](001-action.md)
- [PR #753](https://github.com/onevcat/Prowl/pull/753)
