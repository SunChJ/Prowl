# 063.006 — Workflow Definitions (B1): Plan

## Status

Planned (2026-08-29) — first R2a slice. Owner decisions were settled in a grill session on
2026-08-29 (below) after a re-read of [dsl-spec.md](dsl-spec.md) against what R1 shipped; the
spec's §4/§5/§9/§10/§12 were amended in the same change. Implementation PR: TBD.

## Context

R1 delivered the primitives the runner needs (A1/A2 launch boundary, 064-S1 observer, S2
dispatch receipts, S3 hooks on all eight tier-A runtimes, 065 bundled skills), but the DSL
exists only as a spec. B1 makes it concrete: a file can be parsed, validated, and listed, and
authoring agents get a machine-readable schema. Nothing runs yet — B2 (runner core) and B3
(wiring, `run/status/done/cancel`) follow, with #733 re-dispatch landing before B3.

The spec was written before S2/S3 shipped. Re-reading it against `main` surfaced one
structural overlap (the `expect` completion channel duplicated the dispatch model) and a few
stale rules; those are settled here so B2/B3 do not inherit them.

## Decisions (grilled with onevcat, 2026-08-29)

| # | Decision | Alternatives rejected |
| --- | --- | --- |
| G1 | **Activation = dispatch.** A workflow activation is a record in `AgentDispatchStore`: `launch` steps create it through the S2 prompted-launch path, `message` steps through #733's re-dispatch into an existing surface. `prowl workflow done` resolves the caller pane to its current pending record (peer PID + ancestry, as `dispatch-complete`), requires the activation token to match (correlation only, never trust), validates the body, persists the output, completes the record. `agents wait --dispatch` works on activations. No `WorkflowRequestRegistry`. | A parallel registry + token protocol as first drafted (two "one pending task per pane" mechanisms with drifting semantics). |
| G2 | **Definitions live in `ProwlCLIShared`.** Model, Yams decoding, validator, JSON Schema, and three-source discovery are compiled into both the CLI and the app; `prowl workflow validate` / `schema` run without the app; `list` needs the app (enabled state, worktree-scoped repo source). | App-only parsing with every subcommand over the socket (authoring agents and CI could not validate without a running Prowl; Settings and CLI could not share one validator). |
| G3 | **Watchdog is exact-signal-first and ships in B2** (064-S5's watchdog part moves from D2). `needs-input` → attention immediately; `turn-ended` without delivery → `turn_grace` 15 s (floor 5 s, re-check at expiry) → one nudge → `idle_grace` 3 min → attention; heuristic rules only without a channel. | Heuristic-only watchdog in B2, exact signals retrofitted in D2 (pure rework: hooks already cover all tier-A runtimes). Shorter `turn_grace`: below ~5 s the detector cannot have settled (2 s stabilization + 3 s working hold) and OpenCode can fire `session.idle` twice. |
| G4 | **`launch.prompt` may be multi-line** (A2's `PROWL_LAUNCH_PROMPT` carrier; NUL rejected; 32 KiB cap → `PROMPT_TOO_LARGE`); materialization stays for `message` only. The runner appends the workflow protocol block instead of S2's dispatch block; `dispatch-complete` against an activation fails with `WORKFLOW_DELIVERY_REQUIRED` carrying the exact replacement command. | Keeping the one-line rule; treating a stray `dispatch-complete` as a body-less completion (the step would advance with a missing output). |
| G5 | **`message` injects only into an idle role** (`waitingForRole`). The shipped signal set has no `turn-start`, so a mid-turn injection makes the next `turn-ended` belong to the previous turn and trips S2's `incomplete` rule; the CLI's #733 refusal is the same rule without an observer. Input queueing is assumed to work on every runtime but is not the deciding factor. | Queue semantics as first drafted, with "ignore the first `turn-ended` after injecting into a working role" (real races around Codex's late `turn-ended`). A `turn-start` signal is the V2 path to early injection. |
| G6 | **B1 includes `prowl workflow list`** over the socket, reading a hidden enabled set (`@Shared`, everything enabled until D1's Settings page adds the toggle), so the slice has an app-side surface for the end-to-end pass. | Local `validate`/`schema` only, `list` deferred to B3 (a library-only slice verifiable by unit tests alone). |

## Scope

Owned by 063; nothing here changes 064 code.

- **Yams** as a SwiftPM dependency of `ProwlCLIShared` (`Package.swift`) and of the app target
  (xcodeproj package reference). Pin an exact version. First third-party dependency in the
  Shared directory: remember that Shared sources are also app sources, so no helper may
  collide with an app symbol.
- **Model** (`supacode/CLIService/Shared/WorkflowDefinition.swift` and neighbours):
  `WorkflowDefinition` (schema, id, name, description, icon, inputs, roles, steps), role
  sources `current | launch | pick`, launch requirements (`kind`, `agents`, `suggest`, `bind`,
  `placement`, `direction`, `background`), step verbs (`message`, `launch`, `action`, `notify`,
  `close`, `repeat`), `expect`, inputs (`integer`, `string`, `enum`). Decoding through Yams
  into `Codable` types; unknown keys are errors (spec §7).
- **Validator** (`WorkflowValidator`): every error and warning listed in spec §7, including
  template-variable whitelist checks, producer-dominates-consumer for `outputs.*` /
  `actions.*` / `roles.<r>.pane`, `repeat` rules, verdict/`until` consistency, slug patterns,
  `skill:` resolution against the bundled registry (`ProwlSkills`, 065), and the
  "spells `prowl workflow done`" warning. Diagnostics carry YAML line/column where Yams
  provides them.
- **Action registry (schemas only)**: the V1 native actions `handoff.transition`,
  `handoff.checkpoint`, `git.context` declared with their typed `with` inputs and output keys
  so the validator and `schema` can check references. Execution comes with B2.
- **JSON Schema** (`prowl workflow schema`): generated from the model, checked in under
  `docs-ai/013-prowl-cli/contracts/` beside the CLI output schema, pinned by a test so the
  two cannot drift.
- **Discovery** (`WorkflowDiscovery`): bundle (`Prowl.app/Contents/Resources/workflows/`,
  absent until the first bundled definition ships with D2 — discovery tolerates a missing
  folder) < user (`~/.prowl/workflows/*.yaml`) < repo (`<root>/.prowl/workflows/*.yaml`);
  `prowl.*` ids reserved; repo overrides user for the same non-reserved id. The repo source is
  resolved per worktree by the app.
- **CLI** (`ProwlCLI/Commands/WorkflowCommand.swift`): `prowl workflow validate <file>
  [--json]` and `prowl workflow schema` execute locally (same shape as `SkillsCommandExecutor`);
  `prowl workflow list [--json]` goes through the socket to a `WorkflowCommandHandler` that
  merges discovery with the enabled set. Output contract `prowl.cli.workflow.v1` with a
  `data.action` discriminator (as `prowl.cli.skills.v1`), errors `WORKFLOW_NOT_FOUND`,
  `WORKFLOW_INVALID`, `INVALID_ARGUMENT`.
- **Enabled set**: `@Shared` app storage of *disabled* `(scope, id)` pairs — opt-out, so a
  new file is enabled by default; no UI (D1).
- **Docs**: `docs/components/cli.md` gains the three commands; contract page
  `docs-ai/013-prowl-cli/contracts/workflow.md`; `cli-output-schema.json` updated. The
  `prowl-cli` skill is not taught these commands until B3 makes `run`/`done` real (same rule as
  064.012 B1: never name unshipped commands to agents).

### Non-goals

`prowl workflow run/status/done/cancel`, the runner and watchdog (B2/B3), Settings › Workflows
(D1), bundled definitions and skills (`prowl.handoff`, `prowl.adversarial-review`; D2/D3),
the `Resources/workflows` staging in the Makefile (ships with the first bundled definition).

## Test plan (red first)

- Decoding: the §4 example decodes to the expected model; unknown key, wrong type, and
  duplicate step id fail with positioned diagnostics.
- Validator: one test per §7 error and warning; producer-dominance cases (reference before
  producer, inside vs outside `repeat`); `repeat.max` literal/template bounds; verdict set
  size and `until` literal membership; slug patterns for every id class; `skill:` unknown id.
- Schema: generated JSON Schema equals the checked-in file (drift guard); the §4 example
  validates against it with a JSON Schema validator in the test.
- Discovery: precedence and reserved-id rules over temp directories; missing bundle folder
  tolerated; repo scope resolved from a worktree root.
- CLI: `validate` / `schema` executor tests (JSON and text), `list` socket round trip with a
  stubbed handler, contract schema conformance for every payload shape.

## Verification

`make check`, `make build-cli`, `make test-cli-unit`, `make test-cli-smoke`,
`make test-cli-integration`, `make build-app`, the new Swift Testing suites; then the
end-to-end pass required by the release plan's cadence rules: against an isolated Debug
instance, drop the §4 example into a scratch user `~/.prowl/workflows/`, run `prowl workflow
list --json`, `validate` on the example and on a deliberately broken copy, and `schema`,
driven from the bundled `prowl-cli` skill recipe.

## Open items

- Yams version pin and the xcodeproj package reference (first shared third-party dependency).
- Whether `list --json` should include per-file validation diagnostics inline or only a
  status plus a pointer to `validate` (default: status + counts; diagnostics stay with
  `validate`).
