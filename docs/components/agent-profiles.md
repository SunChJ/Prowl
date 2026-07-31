# Agent Profiles

> Named launch presets for the verified agents (Claude Code, Codex): one click
> in the toolbar **Agents** menu or the Command Palette starts a fresh agent in
> the current worktree with your model, effort, mode, and — optionally — a
> dedicated account.

**Keywords:** agent profile, preset, launch agent, agents menu, dedicated home, account, CLAUDE_CONFIG_DIR, CODEX_HOME, recommended profile

**Related:** [handoff](handoff.md) · [active-agents](active-agents.md) · [command-palette](command-palette.md) · [settings](settings.md)

## What a profile is

A profile is a named preset for one runtime: display name, optional custom SF
Symbol icon, optional model and reasoning effort (both accept free text with
per-runtime suggestions), execution mode (Standard / Unrestricted), and a
launch placement (New Tab or New Split with a direction). By default a profile
is **argv-only**: launching it is exactly like typing `claude`/`codex` with
those flags yourself — same login,
same skills, same session history. The same runtime can have any number of
profiles.

On first run Prowl seeds one bare profile per installed runtime. Seeds are
ordinary profiles: rename, edit, or delete them freely — deleted seeds never
respawn.

## Launching

- **Toolbar Agents capsule** — always opens a popover. With a detected agent it
  leads with Hand Off; launch rows follow, the current worktree's
  **Recommended** profile first. Rows for runtimes that are not installed are
  grayed with the reason. "Manage Agent Profiles…" opens Settings → Agents.
- **Command Palette** (`⌘P`) — "Launch Agent: <name>" rows dispatch the exact
  same action.

A launch creates a **new** tab (or split, per placement) in the current
worktree, running the agent interactively with no initial prompt. Prowl never
types into an existing shell. The new pane records its profile identity at
creation: the Active Agents rows and the capsule show the profile's display
name (frozen at launch — later renames don't relabel live panes).

## Managing profiles

Open **Settings → Agents** to see the ordered profile list. Click a profile to
push its editor; the native Back control returns to the list while the Settings
sidebar remains available. Adding a profile opens the same editor immediately.
Changing another Settings sidebar section leaves the editor and opens that
section's root.

The editor's **Icon** preview opens an SF Symbol picker. A custom symbol appears
where Prowl presents the launch preset: the Settings list, repository Default
Agent Profile picker, toolbar Agents popover, and Command Palette. Clearing it
restores the runtime's Claude Code / Codex brand icon. Live panes and Active
Agents retain the icon of the process Prowl actually detects.

Changing a profile's **Agent** resets its Model, Reasoning Effort, and Extra
Arguments to the new runtime defaults. Those values are runtime-specific; add
new values after choosing the destination agent.

**Recommended** resolves in three tiers: the repo's **Default Agent Profile**
(Repo Settings) → the last profile explicitly launched in this repo → the
first enabled profile in the Settings list order. Each tier only matches an
existing, enabled profile.

## Dedicated home (separate account)

Toggling **Use Dedicated Home** (Advanced) gives the profile its own runtime
home under `~/.prowl/agent-profiles/<uuid>/`, attached to the new surface via
`CLAUDE_CONFIG_DIR` / `CODEX_HOME`. That relocates the runtime's *entire*
home: separate login and usage, but also separate skills, global instructions
(`CLAUDE.md` / `AGENTS.md`), and session history. The first launch is the
sign-in moment — the agent's own TUI walks through login and the credentials
land inside the profile home. Prowl never reads or copies them; use **Reveal
Profile Files** to manage skills and instruction files there yourself.

Removing any profile asks first. Pure presets have no file operations. A bound
profile offers **Remove Profile** to keep its folder on disk and **Remove and
Trash Files** to move the folder to the Trash (never `rm`).

## Advanced extra arguments

The **Extra Arguments** field appends literal argv tokens after the
preset-generated options (quotes group values with spaces; nothing is ever
shell-interpreted). Your flags are respected as-is. The editor stays honest
about what it can prove: recognized bypass flags (`--yolo`,
`--dangerously-skip-permissions`, …) show the red unrestricted warning even
when the picker says Standard; any other extra argument (including
`--sandbox`/`--ask-for-approval`/`-c` overrides) shows a neutral "effective
execution mode follows your extra arguments" note instead of claiming
Standard — the semantics belong to your command line.
The editor's first section is **Launch Preview**. It shows the exact rendered
invocation — including the env prefix for bound profiles — using the same
rendering as the real launch.

## Where things live on disk

| What | Where |
|------|-------|
| Profiles + seeding flag | `~/.prowl/global.onevcat.json` |
| Per-repo default + launch memory | `~/.prowl/repo/<name>/prowl.onevcat.json` |
| Dedicated profile homes | `~/.prowl/agent-profiles/<uuid>/` |

## Gotchas for agents

- Session detection follows the relocated home for Prowl-launched bound panes
  (resume and handoff artifacts resolve against the profile's config root).
  An agent you start manually with your own `CLAUDE_CONFIG_DIR`/`CODEX_HOME`
  is still detected, but without session identity.
- Availability graying uses a heuristic: the runtime's default home
  (`~/.claude` / `~/.codex`) exists iff the CLI has ever run.
- Prowl provides no directory sharing between a bound home and the default
  one. Symlinking read-mostly directories (e.g. `skills/`) yourself works, but
  never link files the CLI rewrites (`settings.json`, `config.toml`,
  `auth.json`) — atomic rewrites replace the symlink and silently diverge.
