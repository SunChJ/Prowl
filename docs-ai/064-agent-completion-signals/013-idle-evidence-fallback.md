# 064.013 — Idle Evidence Fallback: Plan and Action

## Status

Implemented from `fix/agent-wait-idle-evidence` (PR pending). Follow-up to
[012](012-cli-evidence-semantics.md) after a second end-to-end exercise of the bundled
`prowl-cli` skill on 2026-08-28/29 against the Release app built from `main` at `7523ad3d`,
independently re-verified by a second agent.

## Trigger

Nineteen Profile launches across Claude Code, Codex, Pi, and Oh My Pi — two 4-way concurrent
bursts, `DISPATCH_NEEDS_INPUT` → key intervention → succeeded, `DISPATCH_INCOMPLETE`,
`DISPATCH_ABANDONED`, both `AGENT_GONE` modes, `handoff to`, and a hand-launched Claude Code —
all behaved as documented. Two evidence rules did not:

1. `agents wait --until idle` under `auto` timed out on a Profile-launched Claude Code pane
   that had been idle for more than 60 s. Claude's `idle_prompt` notification (fired 60 s after
   a turn ends while the composer sits empty) was decoded as `needs-input`, became the pane's
   active terminal level in place of `turn-ended`, and — because the `verified_live` channel
   advertises `turn-ended` — `allowsHeuristic` refused the detector fallback. The same signal
   satisfied `--until changed` on an idle pane exactly 60 s after arming (armed 15:01:57Z,
   returned 15:02:57Z with `needs-input`/`idle_prompt`), and would satisfy `--until blocked`
   with exact confidence although nothing was blocked. S3b (064.008) had already excluded
   `idle_prompt` for Copilot/Droid/Qoder on the same reasoning; `decodeClaude` still accepted it.
2. `agents wait --until idle` under `auto` timed out on a freshly launched, unprompted Profile
   (Claude Code and Oh My Pi) that the detector reported `idle` after 3 s: the channel had only
   reported `session-start`, no terminal level existed, and the advertised `turn-ended` alone
   suppressed the fallback. `--min-confidence heuristic` resolved in 2 s.

Two documentation gaps surfaced alongside: `worktree.name` is the checked-out branch for Git
worktrees (a checkout mid-run turned `create tab main` into `TARGET_NOT_FOUND`), and a plain
`create tab`/`create pane` always takes focus (`--background` is Profile-only), which let a
person's in-flight keystrokes land in the new shell.

## Decisions

| # | Decision | Alternatives rejected |
| --- | --- | --- |
| C1 | `decodeClaude` accepts the same `Notification` types as the S3b decoder (`permission_prompt`, `elicitation_dialog`); `idle_prompt` throws `unsupportedEvent` and the hook ingress drops it. One shared `acceptedAttentionNotifications` set replaces the two lists. | Mapping `idle_prompt` to an idle-flavoured signal (a new event on the public `agents signal` schema for a runtime-specific timer); special-casing the detail string inside the wait handler. |
| C2 | Under `auto`, a `verified_live` channel suppresses the stabilized heuristic fallback only while the pane's active terminal signal *is* the condition's covered event (`turn-ended` for `idle`, `needs-input` for `blocked`, `session-end` for `exit`); `changed` stays suppressed whenever such a channel exists. A channel with no terminal level, or another level, cannot describe the current state, so the two-second detector view decides. | Keeping the advertised-event rule and documenting `--min-confidence heuristic` as the launch recipe (leaves `auto` — the default — wrong for the skill's own flow); dropping suppression entirely (would let a detector guess pre-empt an exact `changed` edge). |
| C3 | Docs and the skill say `worktree.id` for automation, warn that plain creates take focus, name `.data.anchor.pane.id`, and note that a receipt may precede Codex's own `turn-ended`. Plain `--background` stays a product follow-up. | Implementing `--background` for plain shells in this PR (feature, not a fix). |

Note that C2 alone is not enough for (1): with `idle_prompt` recorded, the active level is a
`needs-input` the detector never corroborates, and only the fallback would end the wait —
heuristically, 60 s after the exact `turn-ended` was already on record. C1 keeps the exact
path intact; C2 covers the no-level case that C1 cannot.

## Delivered behavior

- `AgentNativeHookDecoder`: `acceptedAttentionNotifications` (`elicitation_dialog`,
  `permission_prompt`) is the single accepted list for Claude Code and the S3b runtimes.
- `AgentWaitCommandHandler.allowsHeuristic` takes the current `ConditionSnapshot`: with a
  covering `verified_live` channel it returns `false` for `changed`, and otherwise `false` only
  when `snapshot.signal?.event == coveredEvent`.
- Docs: `docs/components/cli.md` (targeting model, wait fallback, dispatch/receipt timing,
  `create tab` focus note, anchor field), `docs/components/agent-detection.md` (Claude
  notification types), `skills/prowl-cli/SKILL.md`, and the `agents-wait` contract page.

## Verification

- Red first: `autoIdleFallsBackToDetectorWhenLiveChannelHoldsNoTerminalSignal` and
  `autoIdleFallsBackToDetectorWhenLiveChannelHoldsAnotherLevel` failed with `WAIT_TIMEOUT`, and
  the `idle_prompt` case in `claudeNotificationOnlyAcceptsSupportedAttentionTypes` decoded
  instead of throwing; `autoChangedIgnoresDetectorChangesWhileLiveChannelIsPresent` passed
  before and after, pinning the edge suppression that must survive. Green after the change:
  `AgentWaitCommandHandlerTests`, `AgentNativeHookPayloadTests`, `AgentS3bHookPayloadTests`
  (69 tests), the wider agent signal/observation/dispatch/socket suites, `make check`,
  `make build-cli`, `make test-cli-unit` (135), `make test-cli-smoke`,
  `make test-cli-integration` (102), `make build-app`.
- Live, against an isolated Debug instance of the fixed build (`CFFIXED_USER_HOME` scratch
  home, own `PROWL_CLI_SOCKET`, the same `Fable xHigh` Profile): an unprompted launch reported
  `idle` with only `session-start` after 3 s and `--until idle` (auto) resolved in 2 s with
  `confidence: heuristic` (previously `WAIT_TIMEOUT`); after a prompt, `--until idle` resolved
  from `hook_claude` in 2 s; `--until changed` armed on the idle pane ran its full 80 s to
  `WAIT_TIMEOUT` with `signals.last` still `turn-ended` (previously woken at 60 s by
  `idle_prompt`); after that silence `--until idle` resolved immediately with exact
  `hook_claude` evidence and `--until blocked` timed out as it should.
- The live evidence that motivated the change is kept in the session scratchpad
  (`e2e/phase1*.log`, `dispatch-*.log`, `s*.log`, `burst*.log`) and in the independent
  validation run under `/tmp/prowl-independent-validation-20260828-235005`.

## Observed but not changed

- A plain `create tab`/`create pane` has no `--background`; while a person types in the app,
  the new shell receives their keystrokes. Documented; a Profile-free `--background` is a
  product follow-up.
- Codex's `hook_codex` `turn-ended` arrives ~1.8 s after the worker's `dispatch-complete`
  receipt, so the roster shows `working` for that window. Documented as timing, not changed.
