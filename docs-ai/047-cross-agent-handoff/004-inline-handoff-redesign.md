# 047.004 — Inline-First Handoff Redesign

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-21 |
| **Primary PRs** | (this wave) |
| **Related** | [047 plan](000-plan.md), [047.002](002-resume-authored-handoff.md), [047.003](003-plan-calibration.md), [045-native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), `docs/components/handoff.md` |

## Context

A design review of the shipped handoff flow (047.001–047.003) surfaced structural problems
in how the transition acquires its briefing and how the CLI models the source:

1. **The preparation resume mutates the live source session.** The Claude adapter renders
   `claude -p --resume <id> <prompt>` without `--fork-session`; on current Claude Code
   (verified against 2.1.216) `--resume` defaults to *continuing the same session ID*, so a
   headless preparation appends turns to the transcript of a session that is still open in
   the pane — a dual-writer on one JSONL. "Read-only by construction" held for permission
   flags but not for session state.
2. **The CLI has no source identity.** `prowl handoff` reuses the generic target selector;
   with no selector it resolves the *focused* pane — unstable UI state. An agent running the
   documented protocol (`prowl handoff to <agent>` as its last step) triggers a resume of
   *its own mid-turn session*: the fork misses the in-flight turn, overwrites the agent's
   freshly written `current.md` with an older-context reply, and blocks the Bash call for up
   to two minutes.
3. **Stale artifacts impersonate fresh contracts.** When preparation is unavailable, the
   previous `current.md` (or the scaffold template) stays in place and the static kickoff
   prompt still points the receiver at it. The transition archive is also taken *after*
   preparation rewrote the file, so it records the new state, not the outgoing one.
4. **The CLI path hijacks the UI.** `launchHandoffReceiver` selects the target worktree and
   focuses the new tab; an agent-initiated handoff yanks the user's screen.
5. **Resume-fork briefings are structurally worse than they looked.** Transcripts on current
   models persist thinking blocks as *empty signed shells* (measured across 15 recent
   sessions: 300+ blocks, zero non-empty). A forked session cold-reads a record whose
   reasoning layer is empty; the live agent holds the reasoning, the salience ranking, and
   the handoff intent in working memory.

## Decision

Rebuild the handoff flow around one **pure transition function** with an **inline,
agent-authored briefing** as the primary input, executed **headlessly**:

```
transition(source, destination, briefing) =
  archive(previous current.md + context.md)          // outgoing state first
  → current.md ← validated briefing | absent          // never a template, never stale
  → context.md ← live git + session state             // recomputed, not maintained
  → launch destination (background tab, no UI focus)  // headless by construction
  → log + notification
```

### Source identity: caller pane, not focused pane

- Explicit selector (`--pane/--tab/--worktree/target`) wins, unchanged.
- Otherwise the source is the **caller pane**: the CLI service reads the peer PID of the
  socket connection (`getsockopt(LOCAL_PEERPID)`) and walks the process ancestry to the
  pane whose shell owns the calling `prowl` process.
- No selector and no caller pane (invoked outside Prowl) → **error** with guidance. The
  focused-pane default is removed; a handoff must never guess its subject.

### Briefing: inline first, fork as explicit fallback

- **CLI self-handoff** (caller == source): `prowl handoff to <agent> --brief -` reads the
  briefing from stdin. The author is the live agent — full working context, the handoff
  intent, zero extra model calls, zero latency. Missing `--brief` errors with a
  copy-pasteable fix; `--no-brief` is the explicit context-only escape. A brief that fails
  validation errors with zero side effects.
- **UI (HUD / palette)**: no headless resume. Prowl **injects a self-contained instruction
  into the source pane** asking the live agent to run the CLI self-handoff; completion is
  observed via the caller-pane identity (caller == source correlates the CLI call with the
  HUD run). The HUD becomes a trigger + observer with a fallback ladder: wait (queued while
  the agent is busy) → resume-fork → context-only, chosen by the user on timeout. This also
  widens source coverage from claude/codex to every detected agent.
- **CLI third-party** (caller ≠ source): resume-fork remains the default — the author is
  not present. The fork is made side-effect-free: Claude adds `--fork-session`, Codex adds
  `--ephemeral`. On failure/timeout/no-safe-session the transition **degrades to
  context-only and continues** (`preparation=failed` in log and payload) — this path's
  rescue scenario (wedged agent being relieved) must not be blocked by the wedged agent.

### Artifact semantics

- **`current.md` exists ⟺ it is a validated briefing product.** Template seeding and the
  "agent maintains current.md" protocol are abolished; when no briefing is available the
  file is archived and removed, and the kickoff prompt (now generated per-transition)
  points the receiver at `context.md` + `archive/` only.
- Archive-before-write is a global invariant: any write of `current.md` first archives the
  previous version; a transition archives the *outgoing* state before producing the new one.
- `handoff status` and status-transition auto-save are **deleted**: under the pure model
  `context.md` is derived at transition time, nothing consumes it in between, and artifact
  existence is no longer meaningful state. `handoff save` survives, redefined as the
  deferred-handoff checkpoint (briefing + context, no destination/launch/transition log).

### Headless launch and awareness

- The destination tab is created in the source's worktree with `focusing: false` and
  without `selectCLIWorktreeContext`; surfaces start their pty eagerly, so the agent runs
  regardless of visibility. Nothing selects, focuses, or raises.
- A completion notification (`<from> → <to> · <worktree>`, click-to-focus) reuses the bell
  pipeline and its suppression rule (silent when the target worktree is selected and the
  app is frontmost — the appearing tab is the signal there). The HUD, being user-present,
  focuses the new pane itself on completion; the core never does.

## Alternatives considered

- **mtime freshness checks on `current.md`** — superseded: freshness by construction
  (regenerate every transition) removes the need for staleness heuristics entirely.
- **Skip-preparation-when-working guard** — a proxy for self-handoff detection; replaced by
  exact caller-pane identity.
- **Moving handoff under `prowl agents`** — rejected: the CLI grammar is uniformly
  "verb + selector"; the real defect was source identity, not command placement.
- **Uniform resume-fork for all paths** — rejected on evidence: fork latency (≤2 min),
  full-history cost, and empty-thinking transcripts make it strictly worse whenever the
  author is present.

## Implementation

- **Caller-pane identity.** `CLISocketServer.handleClient` reads the peer PID
  (`getsockopt(SOL_LOCAL, LOCAL_PEERPID)`) and threads a `CLICommandContext`
  through `CLICommandRouter.route` to a new context-aware `CommandHandler`
  method (default implementation forwards, so only the handoff handler cares).
  `CallerPaneResolver` walks the caller's ancestry (`proc_bsdinfo.pbi_ppid`,
  bounded) against `WorktreeTerminalManager.paneByShellPID()` — the shell PIDs
  Ghostty already exposes per surface (`bridge.childPID()`).
- **Side-effect-free fork.** `ClaudeCodeRuntimeAdapter` resume renders
  `-p --fork-session --resume`; `CodexRuntimeAdapter` renders
  `exec resume --ephemeral`. Verified against claude 2.1.216 (`--resume`
  otherwise continues the same session ID) and codex 0.144.6.
- **Pure transition core.** `HandoffCoordinator` exposes
  `makeTransitionArtifacts` (collect briefing → `archiveCurrent` →
  `writeBriefing`/`removeCurrentArtifact` → `save`) and `makeCheckpoint`.
  `HandoffBriefingSource` (`inline`/`fork`/`none`) is the explicit input;
  `HandoffBriefing` (`inline`/`fork`/`none`/`failed`) the recorded outcome.
  An invalid inline brief throws before any filesystem write; a cancelled fork
  rethrows `CancellationError` so UI aborts never degrade silently.
  `HandoffStore` lost the template (`ensureLayout` seeds directories +
  `.gitignore` only) and `readStatus`; `validatedBriefing(from:)` keeps the
  fence/preamble normalization.
- **CLI surface.** `handoff status` removed; `--no-prepare` replaced by
  `--brief <text|->` (stdin heredoc) and `--no-brief`; payload schema bumped to
  `prowl.cli.handoff.v2` (`briefing`, `has_briefing`; `preparation`/`exists`/
  `last_log` dropped). New error codes `BRIEF_REQUIRED`, `INVALID_BRIEF`,
  `SOURCE_REQUIRED` carry actionable, copy-pasteable messages.
- **Headless launch + awareness.** `launchHandoffReceiver` no longer selects
  the worktree; `createTab(focusing: false, selecting: false)` (a new
  `selecting` knob down to `TerminalTabManager.createTab(select:)`) starts the
  receiver in a background tab. `notifyHandoffLaunch` posts
  `from → to · worktree` through the existing `appendNotification` pipeline,
  suppressed while the user watches that worktree with the app active.
- **UI as trigger + observer.** `HandoffHudFeature` injects a one-line
  `HandoffInjection.instruction` into the source pane via the new
  `TerminalClient.sendTextToSurface` and waits; the CLI handler announces
  successes through a `completionObserver` → `AppFeature.handoffCliCompleted`
  → `HandoffHudFeature.cliCompleted` (matched on the source pane). Fallbacks
  (`Fork Briefing` when an exact/high session exists, `Context Only`) run the
  same coordinator transition with `source=agents-hud`; the HUD focuses the
  receiver on completion — the core never does. Status-transition auto-save
  was deleted (`AppFeature` state + `handoffAutoSaveEffect`).
- **Docs.** `docs/components/handoff.md` rewritten around the pure transition;
  `cli.md` handoff section, `command-palette.md`, `active-agents.md`,
  `docs/README.md`, and the `prowl-cli` skill updated (the skill now documents
  the self-handoff heredoc as the standard agent posture).

## Verification

- Unit: `AgentRuntimeAdapterTests` (fork/ephemeral argv), `HandoffStoreTests`
  (validation, archive-before-write, removal, no-template layout),
  `HandoffCommandHandlerTests` (briefing decision matrix, zero-side-effect
  rejections, fork degradation removing the stale briefing, kickoff prompt
  adaptation, completion observer), `HandoffHudFeatureTests` (injection
  content, completion matching, fallbacks, cancellation without writes),
  `AppFeatureHandoffTests` (entry points + CLI-completion routing),
  `SupacodeAppCLITests`, CLI parsing + socket round-trip tests
  (`--brief`/`--no-brief`, v2 payload rendering).
- End-to-end (debug app on a dedicated `PROWL_CLI_SOCKET`, driven from a
  sibling Prowl session; full suite: 1954 unit tests green, CLI smoke +
  integration green):
  - **Caller-pane identity**: `prowl handoff` inside a pane with no selector
    resolved that pane as the source (LOCAL_PEERPID → ancestry → shell-PID
    map) and classified it as a self-handoff; outside any pane it returned
    `SOURCE_REQUIRED`.
  - **Inline self-handoff**: `--brief -` heredoc wrote `current.md`
    verbatim, logged `briefing=inline`, launched the receiver in a
    **background tab** (original tab stayed selected/focused), and the
    receiving Claude read the briefing and executed exactly its Next Steps.
    `BRIEF_REQUIRED` / `INVALID_BRIEF` errors verified with zero side
    effects.
  - **Context-only transition** archived and removed the stale briefing;
    the kickoff prompt switched to the no-briefing variant.
  - **Fork fallback**: a real third-party `handoff to` resumed the source's
    session (`claude -p --fork-session --resume`) in ~30 s, produced an
    honest agent-authored briefing, and left the original transcript
    **byte-identical** (fork wrote a new session file) — the dual-writer
    defect this redesign set out to eliminate is confirmed gone.
  - **HUD path**: palette → choose → one-line injection into the live
    agent → the agent wrote its own briefing and ran the CLI itself → the
    completion observer flipped the HUD to "Handed off" and focused the
    receiver. Verification surfaced that the waiting panel swallowed the
    keyboard while the source agent asked for permission approvals — fixed
    by making the requesting stage non-modal (key capture only in
    choosing/finished, focus returned to the terminal, click-outside
    collapses).
  - Observations: session-identity resolution (045) is inherently
    intermittent, so the fork fallback is often unavailable while inline
    always works — reinforcing the inline-first decision. Nested-agent
    environments (`CLAUDECODE` inherited into the debug app) suppress
    transcript persistence and thus session resolution; test-harness
    artifact, not a product defect.
