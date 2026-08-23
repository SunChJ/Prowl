# 064.003 — S2 Paired Dispatch and Agent Wait Design

## Context

S1 merged in #715 and delivered the per-surface signal state, `ObservedAgentState`
multicast observer, lifecycle events, and cooperative `prowl agents signal` ingress. S2 is
the first consumer-facing slice: it must replace hand-written polling with an atomic,
stale-safe dispatch receipt while also making generic state waits honest about their
evidence.

This amendment records the final owner review completed on 2026-08-23. It supersedes the
provisional S2 command spelling in `002-s1-work-note.md`; S1's shipped `agents signal
--detail` contract is unchanged.

## Starting state and confirmed seams

- `supacode/Features/Terminal/BusinessLogic/AgentObservationStore.swift` provides
  snapshot-first, independently buffered multicast observation and retains only the latest
  signal per live surface. It is the right state/signal wait source but cannot retain a
  task receipt after surface closure.
- `supacode/CLIService/AgentSignalCommandHandler.swift` already attributes cooperative
  events through the socket peer's process ancestry. Dispatch completion reuses that trust
  boundary rather than focus or caller-provided pane identity.
- `supacode/Domain/AgentProfile/AgentProfileLaunchPlan.swift` distinguishes child command
  environment from surface shell environment. Only the former is safe for a launch-scoped
  dispatch id.
- `supacode/CLIService/LifecycleCommandHandler.swift` already returns typed profile-launch
  metadata, but prompted launches have no task identity or receipt today.
- `supacode/CLIService/ReadCommandHandler.swift` owns stable viewport capture behavior that
  can supply optional post-wait evidence without redefining completion.
- `supacode/CLIService/CLISocketServer.swift` allows an async handler to suspend while other
  requests are accepted. S2 is the first long-lived CLI wait, so disconnect cancellation
  must be propagated instead of leaving a subscription alive until timeout.
- `supacode/CLIService/Shared/CommandResponse.swift` currently carries only error code and
  message. S2 needs an optional structured error-details field for receipts and last-known
  observation; omitting that field preserves existing wire responses.
- `supacode/CLIService/Shared/AgentsCommandPayload.swift` exposes detected state but no
  signal evidence. S2 adds live observed/verified signal visibility.

Consequently, S2 needs a separate dispatch store and subscriber path while consuming the
S1 observer for status, signal, and lifecycle evidence. Reusing the existing signal record
as receipt storage would lose the result on pane closure and allow unrelated later signals
to overwrite it.

## Scope

S2 ships three connected surfaces in one PR:

1. `create tab|pane --profile ... --prompt ...` becomes an atomic paired dispatch and
   returns an opaque dispatch id.
2. The launched agent reports one immutable terminal outcome through
   `prowl agents dispatch-complete`; `prowl agents wait --dispatch` consumes the resulting
   non-destructive receipt.
3. Generic `prowl agents wait <pane> --until ...`, `--include-screen`, and the `agents`
   `signals` field expose deterministic observations where available and labelled
   heuristics otherwise.

S2 does not install runtime hooks, watch transcript files, infer completion with an LLM,
persist receipts across app restarts, or change `prowl workflow done` semantics. Those
remain owned by S3/S4, the orchestrating skill, and 063 respectively.

## Two planes, one observer context

Signals and dispatch receipts are deliberately separate:

| Plane | Answers | Scope | Storage | Consumer |
| --- | --- | --- | --- | --- |
| Signal observation | What just happened to this agent/runtime? | Surface | Latest in-memory observation; ends with the surface | `wait <pane> --until ...`, later watchdogs |
| Dispatch receipt | Did this exact assigned task reach a terminal outcome? | Opaque dispatch id | Bounded immutable in-memory receipt; survives surface closure | `wait --dispatch <id>` |

`turn-ended` is a runtime edge, not task completion. `dispatch-complete` never fabricates or
maps to `turn-ended`; a normal run may record the dispatch receipt first and receive an
independent runtime `turn-ended` signal afterward. Conversely, a deterministic terminal
signal while a receipt remains pending is actionable evidence that the completion protocol
was not fulfilled, not permission to synthesize success.

## Paired dispatch protocol

Every prompted profile launch is a dispatch. S2 intentionally has no `--no-dispatch` path:

```text
create --profile --prompt
  -> mint pending dispatch
  -> append the versioned Prowl completion instruction to the effective prompt
  -> launch the runtime with child-only PROWL_DISPATCH_ID
  -> return pane identity plus dispatch.id
```

Launch failure removes the pending record and returns the existing typed launch error. The
capacity check and id issuance happen before starting the runtime; binding the returned
surface and completing the create response remain one main-actor lifecycle transaction.

An unprompted `create --profile` remains an interactive launch without a dispatch. A caller
that needs byte-for-byte prompt delivery can create an interactive pane and use the existing
`send` command.

The id must be passed through the launch plan's child-process command environment, not the
surface shell environment. The latter outlives the launched runtime and could let a later,
manually started agent inherit a stale dispatch id. The effective prompt contains the
protocol command but never the id itself.

The injected instruction tells the agent to choose one terminal outcome and make the
completion command its final tool action:

```bash
prowl agents dispatch-complete \
  --outcome succeeded \
  --summary "Implemented the requested change; all tests pass."
```

or:

```bash
prowl agents dispatch-complete \
  --outcome failed \
  --summary "The required SDK is unavailable on this deployment target."
```

`--outcome succeeded|failed` and a non-empty `--summary` are required. Summary is capped at
32 KiB of UTF-8 and is the concise result retained with the receipt, not a transcript or
artifact transport. S1 keeps optional `agents signal --detail`: signal detail is event
context or a reason, whereas dispatch summary is the required terminal delivery synopsis.

The completion command accepts no public dispatch-id option. It reads the child-only
`PROWL_DISPATCH_ID`; the app independently resolves the socket peer's process ancestry and
requires the caller pane to match the dispatch-bound surface. Missing launch context fails
with `DISPATCH_CONTEXT_REQUIRED`; a mismatched caller fails with
`DISPATCH_SOURCE_MISMATCH`.

## Receipt lifecycle and idempotency

The terminal manager owns a separate dispatch store with a maximum of 256 records:

- pending records are never evicted;
- creating a dispatch evicts the oldest terminal record first;
- if all 256 records are pending, creation fails before launch with
  `DISPATCH_CAPACITY_EXCEEDED`;
- succeeded, failed, and gone receipts survive agent and pane closure;
- app restart clears the store, after which an old id returns `DISPATCH_NOT_FOUND`;
- there is no disk persistence or TTL in S2.

Completion is first-write-wins. Retrying the same id with the same outcome and summary is
idempotent and returns the original receipt. A later completion with different content
returns `DISPATCH_ALREADY_COMPLETED` and cannot mutate the recorded outcome seen by existing
or future waiters.

## Wait contracts

### Exact dispatch wait

Dispatch identity is sufficient; a pane argument would be redundant and would stop working
after surface closure:

```bash
prowl agents wait --dispatch <dispatch-id> [--timeout 1...600]
```

Only the matching receipt can return task success. Idle state, screen content, and
`turn-ended` never substitute for it. The outcomes are:

- succeeded receipt: successful command with the immutable summary;
- failed receipt: nonzero exit and structured `DISPATCH_FAILED`, including the receipt;
- exact/high `needs-input`: nonzero `DISPATCH_NEEDS_INPUT`, receipt remains pending;
- exact/high stable `turn-ended` without a receipt: nonzero `DISPATCH_INCOMPLETE`, receipt
  remains pending;
- session end, agent removal, or surface closure before completion: `AGENT_GONE` backed by
  a retained gone record;
- timeout: `WAIT_TIMEOUT` with the last observation and evidence.

Before surfacing `DISPATCH_INCOMPLETE`, the waiter gives a 300 ms coalescing grace period for
independently delivered receipt and signal events. This is an event-ordering allowance, not
screen stabilization. `needs-input` and disappearance remain immediate. A completed receipt
returns immediately unless the caller explicitly requests stable screen evidence.

The receipt read is non-destructive: any number of concurrent or later waiters observe the
same outcome. Socket-client disconnect or CLI cancellation must cancel the server-side wait
subscription rather than leave a waiter alive until the timeout cap.

### Generic observation wait

```bash
prowl agents wait <pane> --until idle|blocked|changed|exit \
  [--timeout 1...600] [--min-confidence exact|high|heuristic] \
  [--include-screen <lines>]
```

The default confidence policy is `auto`:

- when a live exact/high channel is verified, only deterministic evidence resolves the
  requested condition; heuristic changes update diagnostics only;
- without such a channel, an already-stabilized screen/process observation may resolve the
  wait with `confidence: heuristic`;
- `changed` requires a post-baseline normalized state or signal change and is never
  satisfied by the initial snapshot;
- `exit` accepts removal or surface closure; disappearance is `AGENT_GONE` for other
  requested conditions.

An exit-zero heuristic result means only that the requested observable condition matched.
It never means the assigned task completed. The bundled `prowl-cli` skill teaches the
orchestrating agent to inspect `agents read`, optional screen evidence, and task context
before it decides to proceed, nudge, retry, or ask the owner.

`--include-screen` is explicit and diagnostic. After the matching event it reuses the stable
read/capture boundary for a short bounded settle so trailing terminal rendering can arrive;
it never changes the receipt or confidence decision. Existing detector stabilization remains
the heuristic gate instead of adding a universal multi-second delay to exact signals.

Observer overflow is never ignored. The waiter re-subscribes and evaluates a fresh snapshot;
if lost signal history prevents a safe conclusion, it surfaces a structured failure instead
of guessing.

## Signal visibility

`prowl agents --json` reports current evidence, not runtime marketing or theoretical
capability:

- cooperative CLI is listed only after it has been observed on that pane;
- a future S3 hook is listed as verified only after launch injection and self-check succeed;
- the latest signal retains event, source, confidence, timestamp, and optional detail;
- screen/process state remains heuristic observation evidence and does not masquerade as a
  deterministic signal channel;
- no observed or verified deterministic source means an empty `channels` array, enabling
  the generic wait's honest auto fallback.

## Error and response model

The common CLI error envelope gains optional structured details so timeout, protocol, and
task failures can return their last observation or immutable receipt without encoding data
into error strings. Existing errors omit the field and remain wire-compatible.

`create` adds a dispatch object alongside existing launch information. Wait success includes
the dispatch id, outcome, summary, target metadata, completion timestamp, waited duration,
and observation provenance. `DISPATCH_FAILED`, `DISPATCH_NEEDS_INPUT`,
`DISPATCH_INCOMPLETE`, `AGENT_GONE`, and `WAIT_TIMEOUT` use distinct nonzero errors.

## Implementation boundaries

The PR changes the existing launch planner and lifecycle handler under
`supacode/Domain/AgentProfile/` and `supacode/CLIService/`, adds the dispatch store beside
the observation domain under `supacode/Domain/AgentDetection/`, and adds governed wire,
parser, renderer, router, schema, and handler coverage through `ProwlCLI/`,
`supacode/CLIService/Shared/`, `ProwlCLITests/`, and `supacodeTests/`.

The same PR updates the normative contracts under `docs-ai/013-prowl-cli/contracts/`, the
current CLI and agent-detection manuals under `docs/components/`, and the bundled
`prowl-cli` skill. S3 runtime adapter hook injection is explicitly excluded.

## Verification plan

- Dispatch store: issuance, binding, both outcomes, identical retry, conflicting retry,
  two waiters, terminal eviction, all-pending capacity, pane closure, and app-lifetime reset.
- Launch: child-only id propagation, no surface-shell leakage, prompt protocol rendering,
  atomic cleanup on launch failure, and unprompted launch parity.
- Completion ingress: missing context, caller ancestry mismatch, wrong pane, validation,
  summary UTF-8 bounds, and immutable receipt behavior.
- Dispatch wait: already completed, delayed completion, failed outcome, needs input,
  terminal signal grace, gone surface, timeout evidence, cancellation, and concurrency.
- Generic wait: initial snapshot, transition, post-baseline `changed`, exact/high gating,
  auto heuristic fallback, stable screen evidence, overflow resnapshot, and target exit.
- Four CLI layers: parser, shared wire models, router/handler, text/JSON rendering,
  executable schema, raw socket fixtures, and current manuals/skill.
- Required gates before PR: CLI build, smoke and integration tests, format/lint, app tests,
  app build, and live prompted-profile checks for the paired route and heuristic fallback.

## Owner decision record

1. Every prompted profile launch appends the documented completion protocol.
2. Dispatch completion and runtime `turn-ended` remain separate facts and stores.
3. `wait --dispatch` is strict and never accepts an idle or heuristic substitute.
4. Exact/high stable signals may accelerate attention or failure transitions; heuristic
   changes are evidence for the orchestrating agent only.
5. Dispatch uses required `summary`; S1 signal keeps optional `detail` because their content
   roles differ.
6. Completion is first-write-wins with idempotent identical retries.
7. Terminal outcomes are explicitly `succeeded` or `failed`.
8. The store is memory-only, bounded to 256 records, and survives pane closure but not an
   app restart.
9. Generic wait uses deterministic evidence when present and honest heuristic auto fallback
   otherwise.
10. `wait --dispatch` is addressed only by dispatch id.
11. A failed receipt makes wait return nonzero `DISPATCH_FAILED` with structured receipt
    details.
12. The prompted-profile dispatch path has no opt-out in S2.
13. Completion accepts only implicit launch context plus verified caller-pane ancestry.
14. `agents.signals` reports only live observed or verified channels.

No product-level questions remain open for S2. Internal type names and small payload-layout
choices may be refined during RED/GREEN implementation without changing these contracts.
