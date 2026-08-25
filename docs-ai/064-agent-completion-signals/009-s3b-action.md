# 064.009 — S3b Copilot/Droid/Qoder Managed Hooks: Action

## Status

Implemented on `feat/agent-signal-hooks-s3b`. Plan: [008-s3b-plan.md](008-s3b-plan.md).
S3 wave 1 remains incomplete until S3c.

Live acceptance is **partial**: Copilot verified end to end, Droid and Qoder did not reach a
verified channel in the isolated Debug instance. See "Live acceptance" below — this is an open
item, not a passed gate.

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
| Qoder Profile launch and channel | **NOT VERIFIED** |

Droid's hook demonstrably runs (its TUI reports `Hooks Stop … Exit code 0`) but no channel
appears. Ruled out by measurement: missing token (present in the process environment), broken
ancestry (its hook's parent chain is identical to Copilot's), a stripped environment (a marker
variable reaches the hook), payload shape (its fields match the decoder), and cwd form (the
symlink fix above, which did not change the outcome). The remaining suspects are the CLI's
stdin read for this runtime and the first-process-generation timing window; neither was
confirmed because the app's stdout could not be captured reliably in this setup, so the new
rejection diagnostics were never observed.

Qoder could not be exercised because deferred Profile surface creation began failing for every
runtime in that instance while plain tabs kept succeeding — the same symptom as the pre-existing
`deferredProfileAppliesFontSizeAdjustmentAfterSurfaceCreation` failure, which also failed on
`main` at the time and passed again once the isolated instances were shut down.

## Open questions

- Why Droid's hook never produces a channel despite executing successfully. Reproduce with the
  debug rejection log visible (the app must be started so its stdout is actually captured), and
  check whether `readBoundedStdin` returns for this runtime and whether the pane shell's process
  generation is bound before the agent's.
- Qoder's end-to-end path is unverified. Its rendering, merging, and store handling are covered
  by tests, but no live launch has confirmed a channel.
- Deferred Profile surface creation is fragile in this environment. It is not S3b's doing, but
  it blocks live acceptance and is worth understanding before S3c's tier-A gate.

## Refs

- Slice: 064-S3b
- Branch: `feat/agent-signal-hooks-s3b`
- Follows: [007-s3a-action.md](007-s3a-action.md)
