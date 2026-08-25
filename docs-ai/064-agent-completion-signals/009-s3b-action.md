# 064.009 — S3b Copilot/Droid/Qoder Managed Hooks: Action

## Status

Implemented on `feat/agent-signal-hooks-s3b`. Plan: [008-s3b-plan.md](008-s3b-plan.md).
S3 wave 1 remains incomplete until S3c.

Live acceptance is complete: Copilot, Droid, and Qoder are each verified end to end. Droid
needed a fix outside S3b's own code — see "Droid: the launch process is the generation
subject" below.

## Delivered behavior

- `AgentNativeHookRuntime` gains `copilot`, `droid`, and `qoder` (raw value `qodercli`, matching
  `AgentProfileRuntime` so `AgentObservationStore` can keep converting by raw value). The public
  CLI source enum gains `hook_copilot`, `hook_droid`, and `hook_qodercli`.
- One shared Claude-shaped decoder serves all three, with a per-runtime event table and a
  blocking-notification allowlist (`permission_prompt`, `elicitation_dialog`). Only Qoder maps
  `StopFailure`. The session id is read as `session_id` first, then `sessionId`, because
  Copilot's `Notification` — its only needs-input source — is the one mixed-case payload.
- `PermissionRequest` is excluded for all three, and `subagentStop` / `errorOccurred` /
  `idle_prompt` / `auth_success` with it.
- Injection per runtime, in `ManagedHookRendering.swift`:
  - **Copilot** — appends `--plugin-dir` pointing at a static plugin now shipped in the bundle
    (`Resources/agent-hooks/copilot/`, registered as an Xcode folder reference; no Makefile
    change). Its `hooks.json` resolves the CLI as `"$COPILOT_PLUGIN_ROOT/../../prowl-cli/prowl"`.
  - **Droid** — merges the effective (last-wins) user settings and writes the result to an
    owner-only file, then appends `--settings <path>`.
  - **Qoder** — merges the effective (first-wins) user settings and inserts an inline
    `--settings` carrier *before* the user's own, so neither side is silently disabled.
    `--setting-sources` degrades instead of injecting.
- Copilot and Qoder pass their prompt as an option value, so managed options are inserted before
  that option rather than between it and its value.
- `ManagedHookSettings` centralizes settings scanning, merging, serialization, and insertion for
  every settings-based runtime; `ClaudeHookSettingsPreparer` keeps its own scan and behavior.
- Droid's merged settings reach disk through `CodexForwardingRecordStore.createPrivateFile`,
  reusing S3a's `0700`/`0600`, cross-instance session lock, retirement, and orphan sweep. That
  file can hold user secrets such as `customModels[].apiKey`. Only Codex exports a private-file
  locator into the child environment; Droid's path appears solely in its own argv.

## Fix found while verifying

Hook validation compared the launch directory against the hook's reported cwd using
`standardizedFileURL`, which does not resolve symlinks. Runtimes disagree here: Copilot echoes
the shell's logical `/tmp/...` path, while Droid reports `process.cwd()`, which the kernel has
already resolved to `/private/tmp/...`. Both name the same directory, so the comparison now
resolves symlinks first. A rejected hook is silent by design, so `AgentObservationStore` also
logs the first failing precondition in debug builds.

This was a real S3a-era defect that only a runtime reporting resolved paths could expose. It is
covered by `hookCWDComparisonResolvesSymlinkedTemporaryPaths()`, which creates a real
`/tmp` directory because resolution applies only to paths that exist.

## Verification

Repository gates on the branch: `make check` (35 script tests), `make test` (2567 tests, zero
failures), `make build-cli`, `make test-cli-integration` (97 tests), `make build-app`.

Focused coverage lives in `supacodeTests/AgentS3bHookPayloadTests.swift` and
`AgentS3bHookRenderingTests.swift`: the shared lifecycle mapping, Copilot's camelCase
`sessionId`, the notification allowlist, `PermissionRequest` rejection, Qoder-only
`StopFailure`, fail-closed payloads, raw-value round-tripping, per-runtime argv rendering and
degradation, and a store-level pass proving each runtime registers, verifies, and rotates
sessions exactly like Claude.

### Live acceptance

Run in an isolated Debug instance with `CFFIXED_USER_HOME`, a dedicated `PROWL_CLI_SOCKET`, a
scratch repository, and copied agent credentials. No user configuration was modified; scratch
trust entries written by the runtimes were removed afterward.

| Check | Result |
| --- | --- |
| Copilot Profile launch injects `--plugin-dir` before `--interactive` | PASS |
| Copilot reaches `verified_live` with `source=hook_copilot` and a `turn-ended` signal | PASS |
| Bundled plugin loads read-only and resolves the CLI relatively | PASS (also verified with `chmod a-w`) |
| Hook with no token fails open: runtime unaffected, exit 0 | PASS |
| Droid Profile launch injects `--settings` with a `0600` merged file | PASS |
| Droid reaches `verified_live` with `source=hook_droid`, records `session-start` then `turn-ended` | PASS (after the launch-process fix below) |
| Qoder injects inline `--settings` and reaches `verified_live` with `source=hook_qodercli` | PASS (folder must be trusted — see below) |

### Droid: the launch process is the generation subject

Droid's hook demonstrably ran (its TUI reports `Hooks Stop … Exit code 0`) and a stub-socket
test proved the CLI transmitted a well-formed `agentsHook` frame, yet no channel appeared. The
cause was on the app's receiving side, in code S3a and S3b share with every runtime:

- Droid ≥ 0.202 is **two processes**. The interactive TUI is one `droid` process; once the
  folder is trusted it forks a `droid exec --input-format stream-jsonrpc --output-format
  stream-jsonrpc` engine in the same process group, and every hook is a child of that engine.
  Copilot, Qoder, Claude, and Codex are single processes.
- The process probe lists `proc_listpids` output newest-first, and both processes score 80 on
  `argv0`, so the detector identified the TUI at the first scan and the engine as soon as it
  existed (`processes=93538:droid,93296:droid` in the earlier logs was exactly this).
- `AgentObservationStore.updateEvidenceEpoch` keyed the process generation on the identified
  pid. The TUI→engine flip therefore read as a **replaced process**: the managed registration
  was dropped, the private settings file retired, and every later hook rejected at the first
  guard — the one branch whose diagnostic never surfaced because the app's `print` output was
  block-buffered under redirection.

The fix separates two concepts the single-process runtimes had let coincide. `ForegroundProcess`
now carries its parent pid (already in the `proc_bsdinfo` the probe fetches, so no extra
syscall), `ForegroundJob.launchProcessID(of:)` walks to the topmost job member above a pid, and
`IdentifiedAgentProcess` / `PaneAgentState` record that `launchProcessID` beside the identified
`agentProcessID`. State and sessions are still read from the identified process; the process
generation — what a hook's caller ancestry is matched against and what a replacement is judged
by — is the launch process. Hooks descend from both, so an engine child taking over
identification, or being restarted, is no longer a relaunch. Covered by
`AgentClassifierTests.launchProcessIs…` and the two `engineChildRebinding…` tests in
`AgentObservationTests`, which fail on the previous generation subject. The detection diagnostic
now prints `identified=<agent>:<pid> launch=<pid>` so this class of mismatch is visible.

Live, the fixed build bound `launch=52843` at the first scan (engine not yet forked), accepted
Droid's `SessionStart` from the engine child seven seconds later, and recorded `turn-ended`
from `Stop` with `last_binding=current`. The isolated instance used `CFFIXED_USER_HOME` alone
so Prowl's config stayed in a scratch home while the pane shell kept the real `HOME` for
Droid's credentials; `script(1)` gave the app a pty so its debug log was line-buffered.

Two gaps found while narrowing this were fixed along the way and stay in place, though neither
was the cause:

- Session takeover was restricted to Codex and Claude, so once a Copilot/Droid/Qoder channel
  bound a session id, no other session could ever be adopted — a fresh session in the same pane
  (Droid's `/new`) would disable the channel permanently. All Claude-shaped runtimes now adopt
  a new session on `SessionStart`.
- The rejection diagnostics only covered the first guard. The generation, retired-session, and
  session-change branches returned silently. They now log a reason.

### Qoder: resolved — its flag hooks are trust-gated

An earlier reading blamed Qoder's failure on Profile surface creation. That was wrong, and the
correction matters for expectations:

- Profile surface creation is **not** broken for Qoder. On `main` the same Profile launched
  three times in a row, and on this branch seven consecutive Profile surfaces succeeded. The
  intermittent `CREATE_FAILED` seen earlier affects every runtime in a long-lived isolated
  instance, is not caused by S3b, and matches the flaky
  `deferredProfileAppliesFontSizeAdjustmentAfterSurfaceCreation` test.
- The real cause is that Qoder refuses flag-supplied hooks in a folder it has not been told to
  trust, logging `Security: Blocked execution of hook (system) in untrusted folder`. With the
  launch directory trusted, the identical launch reaches `verified_live` with
  `source=hook_qodercli` and records `turn-ended`.

`research-agent-completion-signals.md` claimed Qoder's flag hooks were "not trust-gated". That
entry has been corrected: the original probe ran in a directory that had already been trusted
interactively, which hid the gate. Practical consequence: Qoder gains exact coverage only after
the user trusts the worktree, which they must do anyway before the agent can work there.

### Upgrade re-verification (2026-08-25)

All five managed-hook runtimes were updated to their latest release and re-run through the same
isolated-instance sweep (`create tab --profile` → answer the folder-trust prompt → one prompt →
`agents wait --until idle` → `agents --json`), one after another in one app process:

| Runtime | Version | Result |
| --- | --- | --- |
| Claude Code | 2.1.245 | PASS — `hook_claude` `verified_live`, `turn-ended` |
| Codex | 0.149.1 (from 0.149.0) | FAIL on first run (`managed_hook_degraded`), PASS after the app-server EOF fix recorded in [007-s3a-action.md](007-s3a-action.md) |
| Copilot | 1.0.80 | PASS — `hook_copilot` |
| Droid | 0.203.0 | PASS — `hook_droid` |
| Qoder | 1.1.29 | PASS — `hook_qodercli` |

Every runtime asked to trust the scratch folder first (Claude, Codex, Copilot, Droid, Qoder all
gate on it now), and the launch-process generation held across each engine child. The only
regression came from the one runtime whose version changed, and it sat in preflight, not in the
hook path — a reminder that the notifier resolution talks to a moving protocol and deserves the
live contract test whenever Codex is upgraded.

## Open questions

- Drift protection for the managed-hook contracts (version attestation + headless contract
  tests against the real binaries) is tracked in
  [#726](https://github.com/onevcat/Prowl/issues/726), to be designed once S3c has added
  Pi, Oh My Pi, and OpenCode. Interactive E2E stays a manual runbook aid.
- The launch-process subject also keeps a managed hook alive when a launched agent runs another
  agent CLI as a tool (the nested process is identified, but its launch root is unchanged).
  That case has not been exercised live.
- Deferred Profile surface creation fails intermittently in a long-lived isolated Debug
  instance while plain tabs keep working. It is not S3b's doing — `main` shows the same flaky
  test — but it repeatedly obstructed live acceptance and is worth understanding before S3c's
  tier-A gate.

## Refs

- Slice: 064-S3b
- Branch: `feat/agent-signal-hooks-s3b`
- Follows: [007-s3a-action.md](007-s3a-action.md)
