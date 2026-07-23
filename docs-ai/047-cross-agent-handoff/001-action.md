# 047 — Cross-Agent Handoff: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-09–11 | The original artifact, CLI, palette, auto-save, safety, and target-parsing work was developed in the #551/#554 series. | #550, #551, #554 |
| 2026-07-11 | Native, pid-anchored pane session identity landed separately. | #556 |
| 2026-07-17 | #554 was merged with current `main`: short handles and `pane.agent` now coexist in `prowl list`; the handoff support list includes the current Grok detector. | #554 |
| 2026-07-17 | Replaced the handoff-local Claude/Codex cwd transcript scan with the already-resolved `PaneAgentState.session` metadata from #556. | #554, #556 |

## Outcome & current state (as of 2026-07-17)

- `HandoffStore` under `supacode/Domain/Handoff/HandoffStore.swift` owns the local
  `.prowl/handoff/` scaffold, generated `context.md`, terminal excerpts, append-only log,
  and combined archive snapshots. It never rewrites agent-owned `current.md` after scaffold.
- `ProwlCLI/Commands/HandoffCommand.swift`, `HandoffCommandHandler`, the CLI router, and
  `HandoffCommandPayload` provide `prowl handoff save`, `status`, and `to <agent>`.
  Claude Code and Codex are the only launch adapters; every detected token, including Grok,
  is accepted with `--no-launch`.
- `supacode/App/supacodeApp.swift` reads the selected pane's retained `AgentSession` into
  `HandoffStore.SessionContext`. The session id, source, confidence, and transcript path are
  copied into the handoff artifact only when #556 produced unambiguous evidence; terminal text
  remains a bounded supplementary excerpt.
- Palette actions and `AppFeature` auto-save use that same context without a second filesystem
  scan. Auto-save remains opt-in (existing `current.md`), transition-gated, and throttled.
- `docs/components/handoff.md`, `docs/components/cli.md`,
  `docs/components/command-palette.md`, and `docs/components/workspaces.md` describe the
  current artifact contract and entry points.

## Validation

- `make test` — 1,853 tests passed.
- `make build-app` — Debug app build passed.
- `make test-cli-smoke` — passed.
- `make test-cli-integration` — 63 tests passed.

## Deviations from plan

The first #554 implementation included `HandoffTranscriptResolver`, a second, cwd-based scan
of Claude and Codex storage. It was removed during integration: #556's pid-anchored resolver
is both broader and deliberately refuses ambiguity, so duplicating weaker lookup logic would
risk attaching a sibling pane's transcript.

## Open questions

- Manual end-to-end validation with a live, resolved agent session and a receiving Claude Code
  or Codex tab remains useful before release.
- Capturing a complete final assistant response remains out of scope. Issue #473 proposes an
  opt-in native hook protocol for that separate problem.
