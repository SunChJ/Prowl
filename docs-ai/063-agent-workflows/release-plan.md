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

### Current R1 status (2026-08-27)

| Slice(s) | State | PR / next action |
| --- | --- | --- |
| C0 | Merged | #709 |
| A1 | Merged | #710 |
| A1b | Merged | #713 |
| A2 | Merged | #714 |
| S1 | Merged | #715: bus, multicast observer, `agents signal` |
| S2 | Merged | #718: paired dispatch receipt, strict ID wait, generic evidence wait; [action record](../064-agent-completion-signals/005-s2-action.md) |
| S3 wave 1 | Complete | Merged in #721/#723/#725/#728; S3c plan [064.010](../064-agent-completion-signals/010-s3c-plan.md), record [064.011](../064-agent-completion-signals/011-s3c-action.md) |
| 065-S0/K1 | Merged | #729; [065.003](../065-bundled-agent-skills/003-k1-bundle-registry.md) |
| 065-K2 | In progress | Next 065 slice on `feat/bundled-skills-k2`: shared `SymlinkInstaller` + `prowl skills` |
| 065-K3 | Planned | Follows K2 inside R1 |

A2 completes 063's R1 implementation work, and S1/S2/S3 wave 1 are on `main`. The remaining
R1 work is 065 bundled skill distribution: S0 and K1 are merged (#729); K2 is next, then K3.

#### S3 wave 1 PR breakdown

S3 wave 1 is one complete R1 release slice that landed as three sequential, independently
reviewable PR scopes:

| PR | Runtime scope | Foundation / closure scope | Depends |
| --- | --- | --- | --- |
| **S3a** | Claude Code, Codex | Trusted launch-channel registration, native-hook ingress, payload normalization, self-check/channel lifecycle, bundled hook-resource boundary | S2 |
| **S3b** | Copilot, Droid, Qoder | Plugin/settings adapters and fixtures on the S3a foundation | S3a |
| **S3c** | Pi, OMP, OpenCode | Extension/plugin adapters, complete docs and tier-A live verification (the exact-channel badge was dropped on 2026-08-26) | S3b |

The detailed implementation and verification plan starts in
[064.006](../064-agent-completion-signals/006-s3-wave1-plan.md).

### R1 — CLI orchestration primitives + completion signals

| Order | Slice | Entry | Depends | Outcome |
| --- | --- | --- | --- | --- |
| 1 | **C0** Settings IA: `Section("Agents")` with Profiles (renamed) + Command Line Tool (from Advanced); no Workflows page yet | 063 | — | CLI install lives with Agents |
| 1 | **A1** `prowl create pane` (#699) + anchored split primitive | 063 | 060 | CLI can split |
| 1 | **A1b** `PROWL_PANE_ID` per-pane environment variable (joins `PROWL_WORKTREE_PATH` / `PROWL_ROOT_PATH`) + `prowl-cli` skill self-identification rewrite | 063 | A1 | agents address their own pane deterministically (`--pane "$PROWL_PANE_ID"`) instead of guessing from `focused` |
| 1 | **065-S0/K1** skill-target spike; `embed-skills` + `ProwlSkills` registry | 065 | — | skills ship in the bundle; D1 prerequisite |
| 2 | **A2** profile launch boundary + `create tab\|pane --profile <p> --prompt -` + `profiles list` | 063 | A1 | CLI launches a profile with a kickoff prompt and gets the pane back |
| 2 | **S1** signal bus + `ObservedAgentState` multicast observer + `prowl agents signal` (`turn-ended`, needs-input/session/progress, bounded detail) | 064 | — | layer-0 signals for every runtime |
| 2 | **065-K2** shared `SymlinkInstaller` + `prowl skills list\|install\|uninstall\|path` | 065 | 065-K1 | one command installs Prowl's skills into agent skill folders |
| 3 | **S2** prompted-profile dispatch pairing (`create` dispatch ID, required `dispatch-complete --outcome ... --summary`, 256-entry receipt retention, strict ID-only `agents wait --dispatch`) + generic evidence wait, `source`/`confidence`, `--include-screen`, live `agents.signals`, and skill rubric | 064 | A2, S1 | no hand-written polling or stale completion; deterministic task receipts stay separate from labelled heuristics |
| 3 | **065-K3** Agent Skills section on Settings › Command Line Tool | 065 | 065-K2 | GUI users install skills without a terminal |
| 4 | **S3 wave 1** launch-scoped hooks for tier-A runtimes (Claude Code, Codex `notify`, Copilot, Droid, Qoder, Pi, OMP, OpenCode) + self-check | 064 | S2 | `agents wait` is deterministic for Prowl-launched agents |

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
| 1 | **S4** transcript file-watch + OSC producers | 064 | S1 | layer-2 signals without hooks |

There is no S3 wave 2. Runtimes that require writes to a global config, dedicated home, or
project file do not receive Prowl-managed hooks. The `HANDOFF_RETIRED` stubs are deleted one
release after R3.

### R3+ — V2

063 V2 items (observe mode, `on_attention: ask <role>`, fan-out, retention, run resume,
cross-worktree roles, GUI editor) and the rest of 064-S5; scheduled by demand.

## Dependency graph

```
R1:  C0            A1 ──► A1b
                     └──► A2 ──┐
                               ├──► S2 ──► S3w1
                          S1 ──┘
     065-S0/K1 ──► 065-K2 ──► 065-K3
R2:  B1 ──► B2 ──► B3 (◄ A2, S1) ──► C1 ──► C2 ──► D1 (◄ 065-K1) ──► D2 (◄ S3w1)
R3:  D3 (◄ D2)        S4 (◄ S1)
R3+: V2 / S5 rest;  delete HANDOFF_RETIRED stubs
```

## Change log

- 2026-08-27 — 065-K1 merged in #729. K2 (shared `SymlinkInstaller` + `prowl skills`) started on
  `feat/bundled-skills-k2`; K3 remains planned inside R1.
- 2026-08-27 — 065-S0 completed its target verification and K1 implemented the bundled-skill
  foundation; K2/K3 remain in R1. Record: [065.003](../065-bundled-agent-skills/003-k1-bundle-registry.md).
- 2026-08-27 — S3c merged (#728), completing S3 wave 1 across #721/#723/#725/#728.
  The remaining R1 work is 065 bundled skill distribution.
- 2026-08-26 — S3b merged (#725). S3c started on `feat/agent-signal-hooks-s3c` after a
  live re-attestation of Pi 0.84.3, Oh My Pi 18.0.6, and OpenCode 1.18.23; the Active Agents
  exact-channel badge was removed from S3c without commitment. Plan:
  [064.010](../064-agent-completion-signals/010-s3c-plan.md).
- 2026-08-25 — S3a merged (#721 plus post-merge hardening #723) and S3b started on
  `feat/agent-signal-hooks-s3b`. A local re-attestation of all tier-A runtimes showed that
  Copilot and Qoder emit `PermissionRequest` even when the permission service auto-approves,
  so those two derive `needs-input` from `Notification` only; the same matrix confirmed Claude
  2.1.243 does not, leaving S3a correct as shipped. Plan: [064.008](../064-agent-completion-signals/008-s3b-plan.md).
- 2026-08-24 — S3a implemented the trusted launch registration/epoch boundary, hidden native
  ingress, Claude settings merge, Codex effective-notifier preservation, degradation warnings,
  and focused/live contract coverage. S3 wave 1 remains incomplete pending S3b/S3c.
- 2026-08-23 — S3 wave 2 was removed. Prowl ships launch-scoped hooks only for tier-A
  runtimes that need no global-config, dedicated-home, or project-file writes; Gemini,
  Qwen, Grok, Cline, Kimi, Cursor, and Amp remain on non-hook evidence layers.
- 2026-08-23 — S2 merged in #718 after full gates, authenticated Claude/Codex dispatch E2E,
  and two adversarial review rounds. The next R1 orchestration critical-path slice is S3
  wave 1; 065-S0/K1 remains independent parallel work.
- 2026-08-23 — S2 review corrected the explicit critical path to A2 + S1 → S2 → S3 wave 1;
  S3 consumes the wait/channel/self-check infrastructure delivered by S2 rather than branching
  directly from its two transitive prerequisites.
- 2026-08-23 — S2 implemented on `feat/agent-dispatch-wait-s2`: prompted Profile dispatch
  pairing, immutable receipts, completion/abandonment, strict and generic waits,
  generation-aware evidence, stable screen evidence, peer-EOF cancellation, and live
  `agents.signals`. All gates and isolated Debug E2E completed; draft PR #718 opened.
- 2026-08-23 — S1 merged in #715. Owner review then locked S2: prompted launches always
  create a dispatch, completion has an immutable succeeded/failed summary receipt, strict
  dispatch waits never accept heuristic completion, and generic waits retain honest auto
  fallback. See [064.003](../064-agent-completion-signals/003-s2-dispatch-wait-design.md).
- 2026-08-22 — S1 started on `feat/agent-completion-signal-bus`; owner review moved the
  complete dispatch-ID issuance/receipt/wait protocol into S2, renamed the runtime edge to
  `turn-ended`, retained bounded detail, and required explicit overflow resnapshot.
- 2026-08-22 — A2 merged in #714 after C0 #709, A1 #710, and A1b #713. The next R1
  critical path is 064-S1 → S2 → S3 wave 1; 065-S0/K1 remains independent parallel work.
- 2026-08-22 — A1 review: added **A1b** (`PROWL_PANE_ID`) to R1; `create pane` keeps an explicit
  anchor (no caller-pane default) and a background placement stays with A2.
- 2026-08-22 — first version: three releases agreed; `ObservedAgentState` observer moved
  from 063-B3 to 064-S1; C0 ships without the Workflows page; `prowl agents wait` owned by
  064-S2.
- 2026-08-22 — 065 bundled-agent-skills joins R1 (S0/K1 ∥ A1, then K2, K3); `embed-skills`
  and the skill registry move from 063-D1 to 065-K1, D1 depends on it.
