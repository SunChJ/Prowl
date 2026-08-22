# 064 — Agent Completion Signals: Plan

| | |
| --- | --- |
| **Status** | Planned (per-runtime matrix pending research) |
| **Anchor date** | 2026-08-22 |
| **Primary PRs** | TBD |
| **Related** | [063 agent-workflows](../063-agent-workflows/000-plan.md) (consumer; defines the `ObservedAgentState` observer this entry feeds), [030 agent-status-detection](../030-agent-status-detection/000-plan.md), [045 native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), [055 agent-profile-runtimes](../055-agent-profile-runtimes/000-plan.md), [059 agent-transcript-snapshots](../059-agent-transcript-snapshots/000-plan.md), [060 cli-targeting-and-contract-governance](../060-prowl-cli-targeting-and-contract-governance/000-plan.md), [#473](https://github.com/onevcat/Prowl/issues/473), [#676](https://github.com/onevcat/Prowl/issues/676), `docs/components/agent-detection.md`, `docs/components/cli.md` |

## Background

Prowl's per-pane agent status (`working` / `blocked` / `idle` / `done`) comes from
heuristic screen and process detection (030/045, `supacode/Domain/AgentDetection/PaneAgentState.swift`)
plus the 3 s working hold. It is good enough for the sidebar and Active Agents, and #676
documents the states it still misreports. Two consumers need something stronger:

- An agent orchestrating other agents through the `prowl` CLI (the "route B" flow that
  onevcat runs daily and that 063 formalizes) has to *wait* for a sibling agent to finish.
  Today that means a hand-written polling loop over `prowl agents --json`, a completion
  signal based on a conventional file name, and no way to tell a trustworthy "finished"
  from a heuristic guess. Ten rounds of CLI-driven adversarial review during the 063
  design (2026-08-22) reproduced every one of these pains.
- The 063 runner's watchdog nudges and escalates on heuristic state; a deterministic
  "turn complete" / "needs input" event would make those nudges exact instead of guessed.

Several agent CLIs already expose deterministic, agent-reported events — hooks, notify
commands, plugin events — and most can be enabled per launch without touching the user's
global configuration. Prowl launches agents itself (053/055), so it can attach such hooks
at launch and have the agent report to Prowl through the bundled `prowl` binary.

## Goals

- Introduce one **agent signal bus** per pane that merges four layers of evidence, each
  tagged with `source` and `confidence`:
  0. cooperative signals — `prowl agents signal` (and 063's `prowl workflow done`);
  1. native hooks installed by Prowl at launch (agent-reported, exact);
  2. deterministic observations — native transcript turn-end markers (059), agent process
     exit, OSC progress/notification sequences the CLI emits itself;
  3. heuristic screen/process detection (existing).
- Add `prowl agents signal <event>` so any agent (or a hook it runs) can report
  `turn-complete` / `needs-input` / `session-start` / `session-end`, attributed by the
  caller pane (a hook is a child of the agent process, so process ancestry still resolves
  the pane).
- Add `prowl agents wait <pane> --until … [--timeout] [--min-confidence] [--include-screen]`
  that resolves on the bus and reports *what kind* of signal it got.
- Make `prowl agents` honest about what each pane can offer (`signals` field) and make
  hook installation self-checking with visible degradation.
- Keep per-runtime knowledge in the runtime adapters (055 capability model) with a living
  research matrix, so a changed hook API is a one-adapter change.

### Non-goals

- Making heuristic detection itself authoritative. Layer 3 remains a hint.
- Prowl calling an LLM to judge screens. Judgment belongs to the orchestrating agent (the
  skill gives it the screen tail and a rubric); an on-device Foundation Model classifier is
  at most a V2 experiment.
- Editing the user's global agent configuration (`~/.claude/settings.json`, `~/.codex/config.toml`, …).
  Hooks are attached only through launch-scoped flags/config the adapter has verified; a
  runtime without such a channel simply stays at layers 2–3.
- Waiting semantics inside 063 workflows: the runner still completes steps only on
  `prowl workflow done`; this entry improves its watchdog and enables 063's V2 observe mode.

## Design / Approach

### The bus and its producers

`WorktreeTerminalManager` gains per-surface signal state feeding the typed observer 063
defines (`ObservedAgentState`: `snapshot` / `changed` / `removed` / `surfaceClosed`),
extended with `.signal(AgentSignal)` where

```swift
struct AgentSignal: Sendable, Equatable {
  enum Kind { case turnComplete, needsInput, sessionStart, sessionEnd, progress(Int?) }
  enum Source { case cli, hook(runtime: AgentProfileRuntime, event: String), transcript, process, osc, screen }
  enum Confidence { case exact, high, heuristic }
  let kind: Kind; let source: Source; let confidence: Confidence; let at: Date
  let sessionID: String?; let detail: String?        // e.g. hook payload excerpt; never secrets
}
```

| Producer | Mechanism | Confidence |
| --- | --- | --- |
| `prowl agents signal` | CLI handler, caller-pane attribution, optional `--origin hook:<runtime>.<event>` and `--session <id>` | exact |
| Launch-scoped hooks | adapter capability `signalHooks` renders the launch flag/config that makes the CLI run `<bundled prowl> agents signal --event … --origin hook:…` on its native events (per-runtime syntax: research matrix) | exact |
| Transcript turn-end | 059's reader on the exact/high-attributed transcript, file-watch instead of polling | high/exact |
| Process exit | existing `agentEntryRemoved` | exact |
| OSC | existing progress/notification OSC handling in the Ghostty bridge, surfaced as signals | high |
| Screen/process heuristics | existing detection | heuristic |

Every producer writes to the same per-surface state; the reducer-side consumer (063
runner via `AppFeature`) and the CLI-side consumer (`agents wait` via the multicast
observer) see identical events. Registration and snapshot capture stay one main-actor step.

### `prowl agents wait`

```
prowl agents wait <pane> --until idle|blocked|changed|exit [--timeout 1…600]
                 [--min-confidence exact|high|heuristic] [--include-screen <lines>] [--json]
```

- Snapshot first: return immediately when the current state already satisfies `--until`
  at the required confidence.
- Default `--min-confidence auto`: if the pane has a deterministic channel (a live Prowl
  hook, or an exact/high transcript attribution), only layer 0–2 events resolve the wait;
  heuristic events merely update "last known". Without such a channel the wait resolves
  heuristically once the state has been stable for `stable-for` (3 s hold + 2 s) and says
  so.
- Response: `{status, raw_state, source, confidence, waited_ms, signals: […]}`; with
  `--include-screen N`, a stable `detection`-source screen tail and, when available, the
  059 result state — everything an orchestrating agent needs to judge a heuristic result in
  one call.
- `removed` / `surfaceClosed` → `AGENT_GONE` (unless `--until exit`); timeout →
  `WAIT_TIMEOUT` with the last known status/source. The 600 s cap matches typical agent
  tool timeouts; the skill documents "re-arm on timeout".

### Self-check and visibility

When a Prowl-launched runtime declares a `sessionStart` hook, the launch boundary expects
the corresponding signal within a grace window; if it never arrives the pane is marked
`signals: none` (hooks did not load) instead of silently pretending. `prowl agents`
JSON gains `signals: {channels: [hook, transcript, osc], last: {...}}` per pane, and the
Active Agents panel shows a small "exact" badge for panes with a live deterministic channel.

### Judging heuristic results (skill, not code)

When `source == screen`, the orchestrating agent — not Prowl — decides: the `prowl-cli`
skill ships a rubric (finished answer + empty prompt box vs. spinner/tool output vs. a
permission or question dialog), tells the agent to use `--include-screen` and
`agents read`, and forbids destructive actions on heuristic evidence alone. 063's V2
`on_attention: ask <role>` is the declarative form of the same idea.

### Maintenance rules

- Each runtime's hook support, event → `AgentSignal.Kind` mapping, payload parsing, and
  launch-time rendering live in its adapter (`supacode/Domain/AgentRuntime/AgentRuntimeAdapter.swift`
  family) behind a `signalHooks` capability, with fixture tests for the rendered
  flag/config and for payload decoding. A CLI that changes its hook API is a one-adapter
  change plus a matrix row update.
- `research-agent-completion-signals.md` (living, this folder) records per runtime:
  mechanism, events, per-launch enablement syntax, payload fields, OSC behavior,
  transcript marker, verification method, version, date.
- CLI contracts follow 060's four layers: `prowl.cli.agents.signal.v1`,
  `prowl.cli.agents.wait.v1`, the `agents` `signals` field; schema-validated in socket
  tests; `docs/components/cli.md` and the `prowl-cli` skill updated in the same PRs.

### Delivery slicing

| Order | Slice | Depends | Notes |
| --- | --- | --- | --- |
| 1 | **S1** Signal bus state + `.signal` observer case + `prowl agents signal` (CLI four layers) | 063 B3's observer | Layer 0 works for every runtime immediately |
| 2 | **S2** `prowl agents wait` + `agents` `signals` field + `--include-screen` + skill rubric | S1 | Route B usable; heuristic fallback honest |
| 3 | **S3** Launch-scoped hook injection per runtime (adapter `signalHooks`, self-check) | 063 A2, research matrix | Start with Claude Code and Codex; add runtimes as verified |
| 4 | **S4** Transcript file-watch and OSC producers | S1 | Layer 2 without hooks |
| 5 | **S5** 063 consumption: watchdog uses exact signals; V2 observe mode / `on_attention: ask` | 063 C1+, S3 | Recorded in 063 amendments |

### Verification

Unit: bus merge/ordering, confidence gating, `wait` resolution matrix (already-satisfied,
transition, removal, pane close, timeout, two concurrent waiters), hook rendering per
adapter, payload decoding, self-check degradation. Socket: `signal`/`wait` round trips and
schema. Live: one Prowl-launched Claude Code and Codex pane each — verify hook signals
arrive, `wait` resolves with `source=hook`, and a manually launched agent resolves with
`source=screen` plus screen tail.

## Alternatives & decisions

- **Layered bus rather than a smarter heuristic.** #676 shows the heuristic can be
  improved but never made authoritative for TUIs; deterministic channels exist and should
  be used where present, with honest downgrade elsewhere.
- **Judgment by the orchestrating agent, not by Prowl.** Prowl has no model access worth
  adding for this; the waiting agent already has the task context and can read the screen
  tail that `wait` returns. On-device FM classification is deferred as an experiment.
- **Hooks only through launch-scoped channels.** Mirrors 053/006's launch-scoped
  environment decision: Prowl-launched panes get Prowl hooks; user-launched agents are
  never reconfigured.
- **Separate entry from 063.** The signals are valuable without workflows, touch
  detection/adapters/CLI rather than the runner, and need their own per-runtime
  maintenance; 063 consumes them through one observer type.

## Open questions

- Per-runtime hook/notify/event support, per-launch enablement syntax, and payload shapes
  — being researched; results land in `research-agent-completion-signals.md`.
- Whether hook subprocesses can always reach Prowl's socket from sandboxed runtimes
  (Codex sandbox); `PROWL_CLI_SOCKET` and the bundled binary path must be passed through.
- Exact `stable-for` and self-check grace defaults.

## Amendments

(append `- Updated 2026-MM-DD: ... — see [00N-topic.md](00N-topic.md)` lines here)
