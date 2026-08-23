# `prowl agents signal` Contract

Current version: `prowl.cli.agents.signal.v1`.

```bash
prowl agents signal <turn-ended|needs-input|session-start|session-end|progress>
                    [--progress <0...100>]
                    [--session <id>]
                    [--origin <claimed-origin>]
                    [--detail <short-result-or-reason>]
                    [--json|--no-color]
```

## Semantics

The command reports an observation for the pane that spawned the calling `prowl`
process. It accepts no target selector. The app obtains the kernel peer PID from the
Unix socket, walks process ancestry against live pane shell PIDs, and either attributes the
signal to that exact pane or fails with `SOURCE_REQUIRED`. UI focus and
`PROWL_PANE_ID` are never fallback identity sources.

Events:

- `turn-ended` — the runtime ended one interaction turn; it does not mean an assigned task
  or workflow step completed.
- `needs-input` — progress requires user/agent input.
- `session-start` / `session-end` — producer-reported session lifecycle.
- `progress` — indeterminate when `--progress` is absent, otherwise 0 through 100.

S1 records every public invocation as `source: cooperative_cli`, `confidence: exact`.
Here `exact` means explicit channel plus exact caller-pane attribution; it does not make the
producer's business judgment authoritative. `--origin` is caller-authored metadata only and
cannot upgrade source/confidence or satisfy a future native-hook capability check.

`--session` and `--origin` are non-empty, control-free UTF-8 up to 256 bytes. `--detail`
is non-empty, control-free UTF-8 up to 32768 bytes. Detail is a short result or reason returned
with the signal; it is not logged and does not change confidence. Large results use
`agents read`; workflow outputs use `workflow done -`.

## Success response

Text:

```text
Signaled turn-ended for pane <pane-uuid>.
Signaled progress=75 for pane <pane-uuid>.
```

JSON:

```json
{
  "ok": true,
  "command": "agents.signal",
  "schema_version": "prowl.cli.agents.signal.v1",
  "data": {
    "pane": {
      "id": "6E1A2A10-D99F-4E3F-920C-D93AA3C05764",
      "worktree_id": "/Projects/Prowl"
    },
    "signal": {
      "event": "turn-ended",
      "source": "cooperative_cli",
      "confidence": "exact",
      "at": "2026-08-22T12:00:00.000Z",
      "session_id": "session-1",
      "detail": "Review complete",
      "claimed_origin": "manual-review"
    }
  }
}
```

Optional fields are omitted rather than encoded as `null`. The executable schema is
`#/$defs/agentsSignalResponse` in
[`cli-output-schema.json`](../../../ProwlCLIContracts/Resources/cli-output-schema.json).

## Errors

- `INVALID_ARGUMENT` — invalid event/option combination, progress range, empty value,
  control character, or UTF-8 byte limit.
- `SOURCE_REQUIRED` — the socket peer process cannot be attributed to a live Prowl pane
  (including an external terminal or ancestry broken by tmux/detached wrappers).
- `AGENT_GONE` — the attributed pane closed before the signal was recorded.
- `AGENTS_FAILED` — the app could not encode the signal receipt.

## Deferred paired completion

`dispatch-complete` is deliberately not part of v1 S1. S2 ships one atomic paired path:
CLI `create tab|pane --profile --prompt` returns an opaque `dispatch_id`; the agent reports
`dispatch-complete --outcome succeeded|failed --summary <non-empty-summary>` from its
launch-scoped context; a bounded in-memory receipt survives pane closure but not app restart;
and ID-only `agents wait --dispatch` re-snapshots after observer overflow. Generic runtime
`turn-ended` never substitutes for that dispatch receipt or `workflow done`. This paragraph
is a forward reference, not a shipped command contract; the owner-reviewed S2 design is
[064.003](../../064-agent-completion-signals/003-s2-dispatch-wait-design.md), and normative
wait/completion contracts ship with the implementation.
