# 064.009 — S3b Copilot/Droid/Qoder Managed Hooks: Action

## Status

Implemented on `feat/agent-signal-hooks-s3b`. Plan: [008-s3b-plan.md](008-s3b-plan.md).
S3 wave 1 remains incomplete until S3c.

Live acceptance is **partial**: Copilot and Qoder verified end to end; Droid does not reach a
verified channel. See "Live acceptance" below — Droid is an open item, not a passed gate.

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
| Droid reaches a verified channel | **FAIL — open item** |
| Qoder injects inline `--settings` and reaches `verified_live` with `source=hook_qodercli` | PASS (folder must be trusted — see below) |

Droid's hook demonstrably runs (its TUI reports `Hooks Stop … Exit code 0`) but no channel
appears. A timeboxed follow-up narrowed this to the app's receiving end.

Ruled out by measurement:

- **The whole outbound path works, driven by Droid itself.** With a real Droid run configured
  to call the real bundled CLI against a stub Unix socket, the hook produced a well-formed
  339-byte `agentsHook` frame carrying the correct runtime, event, cwd, and session id. Droid
  also invokes a single-quoted command path containing a space correctly and passes a 570-byte
  JSON payload on stdin. So Droid's own behavior, the command rendering, the stdin read, the
  decoder, and the transport are all correct — the frame reaches the app.
- Token presence, process ancestry (its hook's parent chain is identical to Copilot's),
  environment propagation (a marker variable reaches the hook), payload shape, and cwd form
  (the symlink fix above, which did not change the outcome).

That places the failure entirely on the app's receiving side, even though Copilot and Qoder
traverse the same handler and store successfully. Two contributing gaps were found and fixed
while narrowing this, though neither has been confirmed as *the* cause:

- Session takeover was restricted to Codex and Claude, so once a Copilot/Droid/Qoder channel
  bound a session id, no other session could ever be adopted — a fresh session in the same pane
  (Droid's `/new`) would disable the channel permanently. All Claude-shaped runtimes now adopt
  a new session on `SessionStart`.
- The rejection diagnostics only covered the first guard. The generation, retired-session, and
  session-change branches returned silently, which is why the logs stayed empty even when
  capture worked. They now log a reason.

The remaining candidate is the process-generation match: `callerAncestry.contains(generation)`
compares `AgentProcessGeneration` by both `pid` **and** `startedAt`, so the generation the
detector bound must be the exact process on the hook's ancestry chain. Note also that a
`resolveCaller` failure returns `SOURCE_REQUIRED` before the store runs at all. The next step is
a live run with the completed diagnostics visible.

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

## Open questions

- Why Droid's hook never produces a channel despite the CLI transmitting a valid frame.
  Instrument `resolveCaller` / `recordHook` (a `resolveCaller` miss returns `SOURCE_REQUIRED`
  without reaching the store's diagnostics) and confirm whether the pane shell's process
  generation is bound before the agent's.
- Droid was retested with its launch directory explicitly pre-trusted, so unlike Qoder it is not
  a folder-trust problem: its hook still runs (`Exit code 0`, no "blocked" message) and still
  produces no channel.
- Deferred Profile surface creation fails intermittently in a long-lived isolated Debug
  instance while plain tabs keep working. It is not S3b's doing — `main` shows the same flaky
  test — but it repeatedly obstructed live acceptance and is worth understanding before S3c's
  tier-A gate.

## Refs

- Slice: 064-S3b
- Branch: `feat/agent-signal-hooks-s3b`
- Follows: [007-s3a-action.md](007-s3a-action.md)
