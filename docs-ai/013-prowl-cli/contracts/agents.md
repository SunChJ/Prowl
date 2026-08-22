# `prowl agents` Contract

Current version: `prowl.cli.agents.v1`.

```bash
prowl agents [--json]
```

The command is global discovery and accepts no target selector. It returns
`count` and an `agents` array. Each entry has its canonical pane `id`, detected
agent `type`/`name`, `status`, `raw_state`, optional `detection_reason`,
`last_changed_at`, project/worktree/tab/pane metadata, and optional session
attribution. Text output additionally shows a current-process `pN` handle.

Use `prowl agents read <pN|pane-uuid>` for a semantic agent snapshot. A process inside
a Prowl pane can report cooperative runtime events with `prowl agents signal`; these
commands have separate [read](agents-read.md) and [signal](agents-signal.md) contracts.
The complete roster response schema is
`#/$defs/agentsResponse` in
[`schema-bundle.json`](../../../ProwlCLIContracts/Resources/cli-output-schema.json).
