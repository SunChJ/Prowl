# Agent Workflows (063) + Agent Completion Signals (064) — release plan (living)

> Living document: the single place that says **when** and **in what order** the slices of
> [063](000-plan.md) and [064](../064-agent-completion-signals/000-plan.md) ship. The
> slices themselves — what each PR contains — are defined in the owning plan's
> "Delivery slicing" section. Update this file when scope moves between releases.

## Ownership

| Prefix | Owner | Meaning |
| --- | --- | --- |
| A | 063 | terminal / CLI primitives (`create pane`, profile launch boundary) |
| B | 063 | workflow definitions and runner |
| C | 063 | UI (Settings IA, status center, start sheet, entry points) |
| D | 063 | built-ins, skills, docs, handoff migration |
| S | 064 | completion signals (bus, `agents signal` / `agents wait`, hooks, producers) |

Cross-entry couplings (only these two): 064-S1 delivers the `ObservedAgentState` observer
that 063-B3 consumes; 064-S3 attaches launch-scoped hooks through 063-A2's launch boundary.
063 V1 does not otherwise depend on 064 (steps complete on `prowl workflow done`).

## Releases

PRs merge to `main` one at a time (each keeps `main` shippable); engine PRs without a
user-facing surface may merge before "their" release and stay dormant. Three releases:

### Current R1 status (2026-08-22)

| Slice(s) | State | PR / next action |
| --- | --- | --- |
| C0 | Merged | #709 |
| A1 | Merged | #710 |
| A1b | Merged | #713 |
| A2 | Implemented | #714 |
| S1 | Planned | **Next critical-path PR**: signal bus, multicast observer, `agents signal` |
| S2 | Planned | Follows S1: `agents wait` and honest heuristic fallback |
| S3 wave 1 | Planned | Follows A2 + S1: tier-A launch hooks |
| 065-S0/K1 | Planned, parallel | Skill-target spike + bundled-skill registry |
| 065-K2/K3 | Planned | Follow S0/K1 inside R1 |

A2 completes 063's R1 implementation work. The orchestration critical path now moves to
064-S1 → S2 → S3 wave 1; 065-S0/K1 may proceed independently in parallel.

### R1 — CLI orchestration primitives + completion signals

| Order | Slice | Entry | Depends | Outcome |
| --- | --- | --- | --- | --- |
| 1 | **C0** Settings IA: `Section("Agents")` with Profiles (renamed) + Command Line Tool (from Advanced); no Workflows page yet | 063 | — | CLI install lives with Agents |
| 1 | **A1** `prowl create pane` (#699) + anchored split primitive | 063 | 060 | CLI can split |
| 1 | **A1b** `PROWL_PANE_ID` per-pane environment variable (joins `PROWL_WORKTREE_PATH` / `PROWL_ROOT_PATH`) + `prowl-cli` skill self-identification rewrite | 063 | A1 | agents address their own pane deterministically (`--pane "$PROWL_PANE_ID"`) instead of guessing from `focused` |
| 1 | **065-S0/K1** skill-target spike; `embed-skills` + `ProwlSkills` registry | 065 | — | skills ship in the bundle; D1 prerequisite |
| 2 | **A2** profile launch boundary + `create tab\|pane --profile <p> --prompt -` + `profiles list` | 063 | A1 | CLI launches a profile with a kickoff prompt and gets the pane back |
| 2 | **S1** signal bus + `ObservedAgentState` multicast observer + `prowl agents signal` | 064 | — | layer-0 signals for every runtime |
| 2 | **065-K2** shared `SymlinkInstaller` + `prowl skills list\|install\|uninstall\|path` | 065 | 065-K1 | one command installs Prowl's skills into agent skill folders |
| 3 | **S2** `prowl agents wait` (`source`/`confidence`, `--include-screen`) + `agents` `signals` field + skill rubric | 064 | S1 | no hand-written polling; heuristic results are labelled |
| 3 | **065-K3** Agent Skills section on Settings › Command Line Tool | 065 | 065-K2 | GUI users install skills without a terminal |
| 4 | **S3 wave 1** launch-scoped hooks for tier-A runtimes (Claude Code, Codex `notify`, Copilot, Droid, Qoder, Pi, OMP, OpenCode) + self-check | 064 | A2, S1 | `agents wait` is deterministic for Prowl-launched agents |

User-visible result: onevcat's daily CLI-driven orchestration is first-class
(`create pane --profile --prompt -` → `agents wait` → `send`). Docs: `docs/components/cli.md`,
`agent-detection.md`, `settings.md`, `prowl-cli` skill. Parallelism: C0 ∥ A1 ∥ 065-K1, A2 ∥ S1.

### R2 — Agent Workflows

| Order | Slice | Entry | Depends | Outcome |
| --- | --- | --- | --- | --- |
| 1 | **B1** definitions (Yams, model, validator, JSON Schema, three-source discovery, `workflow list/validate/schema`) | 063 | — | DSL authorable and validatable (may merge during R1) |
| 2 | **B2** runner core (pure state machine, run store, templates, registry, watchdog) | 063 | B1 | — |
| 3 | **B3** runner wiring + `workflow run/status/done/cancel` | 063 | A2, S1, B2 | engine powered on |
| 4 | **C1** status center + run panel + notifications | 063 | B3 | runs visible |
| 5 | **C2** start sheet + entry points (capsule popover, palette, Active Agents) | 063 | B3 | GUI-initiated runs |
| 6 | **D1** `prowl-workflows` authoring skill (skills embedding from 065), `docs/components/workflows.md`, Settings › Workflows page | 063 | B1, C2, 065-K1 | custom workflows, agent-assisted authoring |
| 7 | **D2** `prowl.adversarial-review` built-in + reviewer skill + E2E; watchdog consumes exact signals (064-S5 part) | 063 + 064 | A2, C2, D1, S3 wave 1 | first built-in workflow |

The shipped handoff (HUD + `prowl handoff`) stays untouched in R2. Fallback split if R2 is
too large: R2a = B1–C1 (workflows runnable from the CLI, visible in the status center),
R2b = C2–D2 (GUI entry, Settings, skills, E2E). Default is one R2. Docs: `workflows.md`,
`command-palette.md`, `active-agents.md`, `settings.md`.

### R3 — Handoff migration + signal completion

| Order | Slice | Entry | Depends | Outcome |
| --- | --- | --- | --- | --- |
| 1 | **D3** `prowl.handoff` + `prowl.handoff-checkpoint` built-ins, `HANDOFF_RETIRED` stubs, removal of `HandoffHudFeature` / `HandoffCommandHandler` / `HandoffRequestRegistry`, `docs/components/handoff.md` rewrite | 063 | D2 | handoff is a workflow |
| 1 | **S3 wave 2** tier-B runtimes via dedicated-home profiles (Gemini, Qwen, Grok, Cline, Kimi) | 064 | S3 wave 1, 053 homes | more runtimes exact |
| 1 | **S4** transcript file-watch + OSC producers | 064 | S1 | layer-2 signals without hooks |

The `HANDOFF_RETIRED` stubs are deleted one release after R3.

### R3+ — V2

063 V2 items (observe mode, `on_attention: ask <role>`, fan-out, retention, run resume,
cross-worktree roles, GUI editor) and the rest of 064-S5; scheduled by demand.

## Dependency graph

```
R1:  C0            A1 ──► A1b
                     └──► A2 ─────────┐
                   S1 ──┬──► S2       ├──► S3w1
                        └──────────────┘
     065-S0/K1 ──► 065-K2 ──► 065-K3
R2:  B1 ──► B2 ──► B3 (◄ A2, S1) ──► C1 ──► C2 ──► D1 (◄ 065-K1) ──► D2 (◄ S3w1)
R3:  D3 (◄ D2)        S3w2 (◄ S3w1)        S4 (◄ S1)
R3+: V2 / S5 rest;  delete HANDOFF_RETIRED stubs
```

## Change log

- 2026-08-22 — A2 implemented in #714 after C0 #709, A1 #710, and A1b #713. The next R1
  critical path is 064-S1 → S2 → S3 wave 1; 065-S0/K1 remains independent parallel work.
- 2026-08-22 — A1 review: added **A1b** (`PROWL_PANE_ID`) to R1; `create pane` keeps an explicit
  anchor (no caller-pane default) and a background placement stays with A2.
- 2026-08-22 — first version: three releases agreed; `ObservedAgentState` observer moved
  from 063-B3 to 064-S1; C0 ships without the Workflows page; `prowl agents wait` owned by
  064-S2.
- 2026-08-22 — 065 bundled-agent-skills joins R1 (S0/K1 ∥ A1, then K2, K3); `embed-skills`
  and the skill registry move from 063-D1 to 065-K1, D1 depends on it.
