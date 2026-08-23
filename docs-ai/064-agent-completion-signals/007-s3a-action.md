# 064.007 — S3a Claude/Codex Managed Hooks

## Status

Implemented on `feat/agent-signal-hooks-s3a-implementation`; implementation PR [#721](https://github.com/onevcat/Prowl/pull/721).
S3 wave 1 remains incomplete until S3b and S3c merge.

## Delivered behavior

- Claude Code and Codex adapters now declare only their approved S3a native-event capabilities.
- Profile launch preparation is asynchronous before dispatch issuance. The frozen target,
  inheritance cwd, runtime cwd, home, profile, and config overrides are revalidated before a
  synchronous surface/register/arm/bind transaction.
- Profile surface creation is genuinely two-phase: the exact view/surface identity is installed
  with Ghostty creation deferred, one evidence epoch and hook registration are established, then
  Ghostty is created with its native `initial_input`. Prompted dispatch binding adopts that epoch.
- Arbitrary argv values use typed child-only carriers. Settings JSON, notify overrides, token,
  socket, and forwarding locator never enter typed terminal input; the pane shell does not export
  the public hook token to later manual launches.
- Claude's final effective explicit `--settings` source is merged in memory with stable bounded
  reads. Unknown fields and existing hook arrays survive; Prowl handlers deduplicate; malformed,
  changed, unreadable, non-object, and oversized sources launch unchanged with one warning.
- Codex effective `notify` resolution uses its bounded official app-server initialize +
  `config/read` JSONL protocol. Base config, profile-v2 files, and final top-level CLI override are
  resolved without reading provider fields into logs or durable state. Project `notify` remains
  excluded by Codex itself.
- Existing Codex notifiers are preserved through random owner-only records and a hidden bundled
  CLI dispatcher. The bridge leases/reads before transport, keeps exact argv boundaries, scrubs
  internal environment, and `exec`s the notifier with the original payload even after listener
  loss. Trust revocation is immediate; retirement and orphan cleanup are lease-aware.
- The hidden `agents _hook` parser is absent from help/completion. Claude stdin and Codex final-argv
  payloads are bounded and normalized without `last_assistant_message`. The app accepts only an
  exact token/pane/runtime/event/cwd/generation registration and then exposes
  `hook_claude|hook_codex` as `verified_live`.
- Safe preparation failure never blocks the runtime: GUI launches show one warning toast; CLI
  success adds optional `warnings: [{code: "managed_hook_degraded", runtime, message}]`. JSON keeps
  it in stdout and text renders it exactly once to stderr.
- The Settings Launch Preview remains the deterministic base invocation. Conditional execution
  settings, tokens, socket paths, and forwarding locators are prepared only after live preflight
  and stay redacted. This is more honest than rendering a Codex override that may be omitted after
  notifier degradation; current docs now state that boundary explicitly.

## Phase 0 runtime evidence

Re-attested 2026-08-24:

- Claude Code `2.1.241`; Codex CLI `0.149.0`; Pi `0.84.2`.
- Claude repeated `--settings` is final-source-wins. A scratch authenticated run produced
  `SessionStart`, `Stop`, and `SessionEnd`; only the final settings handler fired. The observed Stop
  payload included `last_assistant_message`, which the bridge deliberately excludes.
- Codex app-server accepted initialize/initialized/`config/read` against scratch homes. Effective
  `notify` was `null` for a clean home, preserved exact Unicode/empty argv from base config, and
  reflected final `-c notify=...`. A trusted project layer loaded unrelated values but still
  excluded project `notify`.
- Codex profile-v2 is `$CODEX_HOME/<name>.config.toml`; app-server rejects `--profile`. Prowl
  therefore stable-reads only that file into an owner-only parser home and asks Codex to parse it
  as temporary user config.
- Contrary to the frozen plan's “last cwd wins” wording, 0.149.0 rejects repeated `-C/--cd`.
  Separate, joined (`-Cdir`), and equals forms are supported. Prowl autonomously chose the safe
  behavior: repeated cwd degrades managed hooks and preserves the original (runtime-rejected)
  launch rather than inventing an effective cwd.
- A real authenticated Codex notify run produced `agent-turn-complete` as the final argv with
  thread id, turn id, cwd, and last assistant message. Sanitized payload fixtures retain the
  shape while excluding real IDs/results.

All scratch probes guarded the live Claude/Codex config hashes. Runtime-added trust/state entries
were removed only when the current hash still matched the probe result, restoring the exact
pre-probe hashes.

## RED → GREEN record

Focused failing tests were observed before each logic layer existed:

1. native payload decoding, adapter capabilities, Claude settings merge, Codex notify rendering,
   and arbitrary argv carriers;
2. app-server JSONL parsing, notifier absence/presence/profile/override precedence, cwd/profile
   option parsing, malformed/recursive degradation;
3. forwarding record permissions, exact argv, shared-read/exclusive-cleanup leases, retirement,
   and orphan sweep;
4. pending early-hook activation, exact rejection matrix, verified coverage, session rotation,
   process replacement, and one-epoch dispatch adoption;
5. hidden CLI parsing, schema, kernel peer-PID socket routing, silent listener loss, exact notifier
   `exec`, environment scrub, warning omission/output channels, and preflight cancellation.

The first live Debug attempt exposed a real race not visible in pure tests: sending text immediately
after creating an unarmed surface could lose the command before the shell was ready. That approach
was removed. Regression coverage now asserts that the view/tree/profile identity is installed while
Ghostty creation is still unarmed, and that native `initial_input` is armed only after registration.

## Validation

Focused app suites: 100+ managed-hook/profile/CLI/lifecycle tests passing. The live Codex
`config/read` contract test passed against 0.149.0 with scratch absent/base/profile/override and
project-exclusion fixtures. CLI subprocess integration proved silent zero-exit listener loss and
exact notifier forwarding with empty/Unicode argv, unchanged payload, scrubbed internal variables,
and original notifier exit status.

Repository gates passed on the implementation branch: `make build-cli`, `make test-cli-smoke`,
`make test-cli-integration` (95 integration tests), `make check` (including 34 script tests),
`make test` (xcresult verified 2506 tests, zero failures), and `make build-app`. The enabled live
Codex 0.149 scratch contract also passed.

The full Debug GUI matrix was attempted with a freshly embedded bundle CLI, custom socket,
`CFFIXED_USER_HOME` scratch Prowl state, scratch workspace, owner-only Codex homes/auth copies, and
hash guards proving live Claude/Codex config restoration. The host GUI session was at `loginwindow`:
LaunchServices created the Debug process/socket but no visible main window, while direct launch had
no display and Ghostty reported `CVDisplayLink` invalid display count / surface initialization
failure. No shell/agent process could exist, so these GUI rows remain `INCONCLUSIVE`, not PASS. The
real framed socket/peer ancestry path, deferred pre-input registration ordering, hook decoding,
listener loss, notifier forwarding, and app composition are executable automated coverage; the
single-app visible-pane matrix remains a required manual/owner follow-up when a GUI session is
available.

## Adversarial review

### Round 1 — trust, launch transaction, epochs, and forwarding lifecycle

The first independent full-diff review blocked on five valid P1 findings. All were reproduced
against the current code and corrected with focused regression coverage:

- Codex preflight now resolves an absolute executable plus `HOME`/`CODEX_HOME` through the same
  non-logging login-shell environment a Profile command uses. An unprovable/non-absolute result
  degrades without injection; the app's launchd PATH/home can no longer authorize notifier
  replacement.
- Peer/task cancellation is checked after every preparation await, before and after forwarding
  record creation, and immediately before dispatch issuance. Capacity/failure/cancellation paths
  explicitly discard unexposed records; the cancellation test deliberately returns a successful
  preparation after observing cancellation and still proves no issue/launch.
- Managed-hook session identity is independent from detector hints. Detector `nil` cannot erase a
  verified session, and detector-first same-process replacement remains unverified until Claude
  sends the matching `SessionStart`.
- Deferred Ghostty arming now fails when `ghostty_surface_new` returns nil, resets its armed state,
  and rolls back the exact tab/split registration instead of reporting a launch with no process.
- Forwarding cleanup initializes an orphan sweep at app startup and owns a clock-driven retry loop
  until every retired record can take the exclusive lease; one busy first pass no longer leaves
  sensitive argv indefinitely.

The review also confirmed the peer-PID ancestry boundary, pre-input order, bounded early-event
buffer, exact cwd rejection (including memories), hidden bridge silence/deadline/`execvp`, payload
exclusion, carrier redaction, and owner/mode/no-follow/lease checks. Focused validation after the
fixes passed 89 tests plus `make check` (34 script tests).

## Deferred scope

S3b owns Copilot/Droid/Qoder adapters. S3c owns Pi/OMP/OpenCode adapters and the Active Agents exact
badge. Manual launches and those runtimes remain on existing cooperative/transcript/process/screen
evidence in this PR.
