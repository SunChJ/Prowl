# `prowl agents wait` and dispatch contracts

## Status

Current versions:

- `prowl.cli.agents.dispatch-complete.v1`
- `prowl.cli.agents.dispatch-abandon.v1`
- `prowl.cli.agents.wait.v1`

## Exact dispatch completion

Every prompted `create tab|pane --profile … --prompt -` returns a pending dispatch. The
launched child receives its id through `PROWL_DISPATCH_ID`; callers cannot supply an id to
completion manually.

```bash
prowl agents dispatch-complete --outcome succeeded|failed --summary <text> [--json]
```

`--summary` is required, control-free, and limited to 32768 UTF-8 bytes. The app resolves the
socket peer ancestry and requires the caller to belong to the dispatch-bound surface.
Completion is first-write-wins: an identical retry replays the receipt, while a conflicting
outcome or summary fails. `turn-ended` is observation only and never becomes success.

Success returns `target`, completed `receipt`, and `replayed`. The immutable receipt contains
`id`, `state=completed`, `outcome`, `summary`, `created_at`, and `completed_at`.

## Explicit abandonment

```bash
prowl agents dispatch-abandon --dispatch <id> --reason <text> [--json]
```

Abandonment terminalizes only the coordinator's retained record. It does not stop, close,
succeed, or fail the worker. A retry against an already terminal record (completed, abandoned,
or gone) fails with `DISPATCH_ALREADY_TERMINAL`; later completion is rejected.
Pending records never expire or evict automatically. The in-memory app-lifetime store holds
at most 256 records and evicts the oldest terminal record first; if all 256 are pending, a new
prompted launch fails before creating a surface.

## Exact dispatch wait

```bash
prowl agents wait --dispatch <id> [--timeout 1...600] [--include-screen 1...200] [--json]
```

Dispatch mode is id-only and rejects pane, condition, and confidence options. A succeeded
receipt returns success with `mode=dispatch`, `waited_ms`, immutable `target`, `receipt`,
current `signals`, and optional stable `screen`. Failed, abandoned, gone, needs-input,
incomplete-turn, and timeout outcomes are nonzero structured errors. Known-dispatch error
details retain `mode`, `waited_ms`, `target`, the current tagged-union `record`, available
observation/signal evidence, and stable `screen` evidence when requested.

`turn-ended`, matching `session-end`, and surface close open a 300 ms completion-priority
window. A completion arriving inside the window wins; otherwise waits report
`DISPATCH_INCOMPLETE` or retained `AGENT_GONE`. Detector removal alone is diagnostic. Multiple
waiters are non-destructive. App restart resets all receipts.

## Generic condition wait

```bash
prowl agents wait <pane> --until idle|blocked|changed|exit \
  [--timeout 1...600] [--min-confidence auto|exact|high|heuristic] \
  [--include-screen 1...200] [--json]
```

The pane is resolved once to a stable target. `changed` requires a post-baseline revision;
`exit` requires the surface to stop being live. Exact surface closure satisfies `exit`; for
`idle`, `blocked`, or `changed` it returns structured condition-mode `AGENT_GONE` immediately.
Exact/high current-epoch cooperative evidence wins. `auto` may fall back to a heuristic
idle/blocked match only after the observed state and revision remain unchanged for two
seconds, and only while no covering `verified_live` channel holds a terminal signal (a channel
that has only reported `session-start` does not suppress the fallback; one holding an opposite
level does, so exact evidence is never overridden by the screen). `changed` and `exit` never
fall back while such a channel exists: `exit` then resolves on `session-end` or surface closure.
Higher minimum-confidence settings reject weaker
evidence rather than relabelling it.

`idle` and `blocked` are state observations, not edge detectors. The active terminal signal
present when the wait was armed satisfies the condition only when the screen detector
corroborates it (`idle`/`done` for `idle`, `blocked` for `blocked`); a signal that arrives
after arming satisfies it on its own. `changed` is the edge wait. The reported
`observation.status`/`raw_state` are the detector's view at match time; `source` and
`confidence` describe the evidence that matched.

A pane with no detected agent is not an immediate failure: the wait polls for up to
`agentAppearanceGraceMilliseconds` (10 s), bounded by `--timeout`, and only then fails with
`AGENT_NOT_FOUND` carrying condition-mode details (`waited_ms`, `target`, `signals`, optional
`screen`). Once an agent has been seen, its later disappearance does not end the wait.

Evidence is bound to PID plus process start time and, when known at exact/high confidence,
the current session id. A dispatch launch accepts its first detected process generation only
when that process started within ten seconds of binding; a later-started process is a
replacement epoch even if the original runtime escaped detection. Medium-confidence session
guesses remain diagnostic and never bind or rotate an evidence epoch. PID reuse, delayed
children, replaced sessions, mismatched sessions, and unverifiable sessionless signals remain
diagnostic only. Generic success and timeout
details report the actual source, confidence, timestamp, revision, and current signal channels.

When requested, screen evidence reads the detection buffer every 200 ms until unchanged for
800 ms, capped at two seconds, and returns only the requested trailing lines. Success payloads
and structured wait errors both retain it. It is evidence, not completion proof.

## Cancellation and schemas

After consuming a request frame, the app monitors the Unix peer without consuming response
bytes. EOF, unexpected extra input, or task cancellation cancels the route and unregisters
wait-store subscribers promptly; no response is written to a disconnected peer.

All dispatch records and wait mode/screen payloads are strict tagged unions with
`additionalProperties: false`. Errors may include governed `error.details`; legacy errors
omit it. Canonical executable schemas live in
[`cli-output-schema.json`](../../../ProwlCLIContracts/Resources/cli-output-schema.json).
