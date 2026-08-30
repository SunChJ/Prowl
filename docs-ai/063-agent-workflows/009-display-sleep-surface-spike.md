# 063.009 — Display-Sleep Surface Creation Spike

## Status

Accepted investigation, 2026-08-30. The spike ran against `main` at `299b5a5d`, which includes
[#744](https://github.com/onevcat/Prowl/pull/744). It produced no production-code change: every
experimental edit was reverted after the result was established.

This is not an R2a release blocker. It does establish a required follow-up: an interactive
workflow launch needs an explicit policy for a display-unavailable failure instead of depending
on Ghostty surface creation indefinitely.

## Problem summary

Long-running agent work commonly continues while the Mac display is asleep. In that state, a
CLI-driven Agent Profile launch can fail with `CREATE_FAILED`:

> The terminal surface for Agent Profile “…” could not be created.

Earlier live verification had already correlated this with a zero-display Ghostty failure:

```text
CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)
com.mitchellh.ghostty:embedded_window: error initializing surface err=error.OutOfMemory
```

`pmset -g log` showed `Display is turned off`; waking the display made the same launch succeed.
The immediate question for this spike was narrower than designing a fallback:

> Can Prowl preserve an interactive launch by changing when or how it creates and attaches the
> Ghostty surface while the display remains asleep?

## Current launch boundary

An Agent Profile launch intentionally stages the Swift-side tab/split with
`defersSurfaceCreation: true`, registers the managed signal channel through
`onAgentProfileSurfacePrepared`, and then calls `GhosttySurfaceView.armSurfaceCreation()`.
Failure rolls the tab or split back and becomes `.surfaceCreationFailed`.

This ordering is required for managed hooks: the launch-scoped environment must be prepared
before the child process starts. It also makes the Profile path honest about native creation
failure.

Ordinary tab and split creation use the immediate `GhosttySurfaceView` initializer instead. The
initializer calls `armSurfaceCreation()` but discards its Boolean result. Consequently, the
Swift-side tab or split can be returned even when `ghostty_surface_new` returned `nil`. A visible
tab UUID is therefore not evidence that a working terminal surface exists.

Relevant boundaries:

- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- `supacode/App/WorkflowRuntimeComposition.swift`
- `supacodeTests/WorktreeTerminalStateAgentProfileTests.swift`

## Method

The live checks used a separately launched Debug app with a scratch `CFFIXED_USER_HOME` and a
dedicated `PROWL_CLI_SOCKET`; the installed Prowl instance and its sessions were not replaced.
Display state was driven with `pmset displaysleepnow` and verified from `pmset -g log`. A
`caffeinate -d -u -t 3` wake trap restored the display after each bounded attempt. One sample was
discarded because the display was manually woken before it completed; the conclusions below use
only attempts that remained in the logged display-off interval.

Experimental code lived temporarily on `spike/profile-launch-display-sleep`. The spike added
targeted logging and, for the detached-staging hypothesis, a regression test. All changes were
then reverted, the isolated app was stopped, its scratch state was moved to Trash, and the
temporary branch was deleted.

## Experiments

| Experiment | Result | Interpretation |
| --- | --- | --- |
| Baseline Profile launch with the display awake | Succeeded | The current #744/Profile/CLI wiring is functional under its normal display precondition. |
| Unmodified Profile launch during a stable display-off interval | Failed with `CREATE_FAILED` at native surface creation | Reproduced the known issue on current `main`. |
| Build the Swift tab/split structure detached, prepare hooks, then attach and arm the surface | Unit test was red before staging and green after it; real tab and split Profile launches still failed while the display was off | Tree attachment and managed-hook ordering are not the cause. The promising unit result modeled Swift ordering, not Ghostty's display dependency. |
| Disable deferred creation and create the native Profile surface during initialization | Failed while the display was off | Deferral itself is not the cause. |
| Remove Ghostty `initial_input` and attempt post-create text injection | Failed before input could be delivered | Initial input is not the cause. |
| Remove the Profile launch's `surfaceEnvironment` | Failed while the display was off | Launch-scoped carriers and managed-hook environment are not the cause. |
| Create ordinary tabs and splits with temporary logging at the native boundary | Swift-side creation returned identifiers, but the log showed native Ghostty surface creation failed | The apparent fallback was a false positive: these paths ignore the failed arm result and leave a non-functional shell. |
| Wake the display and repeat the same Profile launch | Succeeded | The failure follows display availability, not #744's workflow wiring or the selected Profile. |

The detached-staging test exercised the desired hook-before-tree ordering and passed as a logic
test, but the real display-off result falsified the product hypothesis. Its implementation and
test were therefore not retained.

## Conclusion

In the tested build and environment, every path that ultimately calls `ghostty_surface_new`
needs an active display. Reordering Swift objects, bypassing `initial_input`, omitting the Profile
environment, or choosing immediate rather than deferred creation does not avoid that native
precondition.

The Ghostty log reports `error.OutOfMemory`, but the adjacent CVDisplayLink diagnostic and the
repeatable display-off/display-on boundary show that this case is display unavailability, not
ordinary memory pressure. Prowl should not expose it only as generic `CREATE_FAILED`.

The spike therefore rejects “create the same interactive surface differently” as the fallback.
A path that truly works without a display must not create a Ghostty/AppKit terminal surface.

## Recommended follow-up

### 1. Make display unavailability a typed launch outcome

Add a display-availability preflight at the closest reliable launch boundary and retain a
postcondition check around native surface creation. Map the known zero-display case to a typed
error such as `DISPLAY_UNAVAILABLE` (provisional name), distinct from hook registration,
Profile planning, authentication, and unknown native failures.

The preflight improves error quality and avoids reserving workflow state for a launch that
cannot start. It must not replace the native result check because display state can change
between preflight and creation.

### 2. Make ordinary tab and split creation honest

The non-Profile paths should not return a usable target identifier after native creation failed.
They should check the arm result, roll back the Swift tab/split/target state, and return a typed
failure. This does not solve display sleep, but it removes a misleading fallback and prevents
dead terminal shells from entering the model.

### 3. Add an explicit interactive-launch failure policy

For a workflow role declared as `kind: interactive`, introduce a policy scoped specifically to
the typed display-unavailable outcome:

```yaml
roles:
  reviewer:
    source: launch
    kind: interactive
    on_display_unavailable: headless # proposed default
```

The initial choices should be:

- `headless` — default; run the role without a Ghostty surface when the runtime supports the
  required headless contract.
- `fail` — opt out of substitution and move the workflow to explicit attention/failure.

The key name and exact state vocabulary remain design work. The important boundary is that this
must not become a catch-all fallback for arbitrary `CREATE_FAILED`: hook, Profile, credential,
renderer, and unknown native failures still fail closed.

### 4. Specify the headless executor before enabling the default

`kind: headless` is already reserved for V2 in [the DSL specification](dsl-spec.md#12-reserved-for-v2),
but no executor exists. A production `HeadlessAgentExecutor` needs at least:

- explicit cwd and bounded environment construction;
- process-group cancellation and timeout semantics;
- bounded stdout/stderr capture and persisted diagnostics;
- per-runtime invocation rendering and trusted result extraction;
- runtime capability gating and a deterministic unsupported-fallback outcome;
- the same output validation and workflow-delivery trust boundary as interactive roles.

This is a real release-scope expansion if pulled into R2a. The accepted spike only establishes
the direction; it does not silently move the full V2 headless contract into R2a.

### 5. Preserve workflow semantics when substituting execution modes

An interactive role may be launched once and later receive `message`, `repeat`, `focus`, or
`close` steps. A one-shot headless subprocess is not automatically equivalent. Before allowing
fallback, validation or admission must prove that the runtime/executor can preserve the role's
lifetime and re-dispatch semantics; otherwise the run should use the configured `fail` behavior
and surface actionable attention.

C1 should eventually make these cases visible as separate states: falling back to headless,
fallback unsupported, and display-unavailable with `fail`. The fallback decision must be
persisted in `run.json` and exposed by `workflow status` so the execution mode is never hidden.

## Release impact

R2a remains B3 plus C1 as recorded in [the release plan](release-plan.md#r2a--workflow-engine-and-cli).
This spike is accepted as a known environmental limitation rather than an R2a blocker. For R2a
verification, keep the display awake so the interactive contract being released can be tested
deterministically.

The recommended next planning slice is narrow:

1. define and test the typed display-unavailable classification and honest ordinary-creation
   rollback;
2. decide whether R2a ships only the explicit `fail` behavior or pulls in a minimal capability-
   gated headless executor;
3. if headless remains V2, record the limitation in user-facing workflow documentation and keep
   the full fallback behind the V2 executor contract;
4. include fallback/unsupported/fail presentation in the C1 state model, without blocking C1's
   existing provisional-delivery controls.

## Non-goals of this spike

- No production fallback was implemented.
- No virtual-display, screen-wake, or Ghostty-fork workaround was attempted.
- No fallback was proposed for arbitrary launch failures.
- No claim was made that a headless process preserves interactive pane semantics without the
  executor and capability contract above.

## References

- [063.008 — Workflow Runner Wiring (B3)](008-b3-runner-wiring.md)
- [063 workflow DSL, V2 reservations](dsl-spec.md#12-reserved-for-v2)
- [064.011 — S3c action, original display-sleep finding](../064-agent-completion-signals/011-s3c-action.md#display-sleep-is-the-create_failed-behind-the-intermittent-profile-launches)
- [065.005 — K3 settings and verification note](../065-bundled-agent-skills/005-k3-settings-agent-skills.md)
