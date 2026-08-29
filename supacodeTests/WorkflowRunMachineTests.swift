import Foundation
import Testing

@testable import supacode

// swiftlint:disable file_length type_body_length
struct WorkflowRunMachineTests {
  // MARK: - Fixtures

  nonisolated static let adversarialReview = """
    schema: prowl.workflow/v1
    id: prowl.adversarial-review
    name: Adversarial Review
    inputs:
      max_rounds: { type: integer, default: 5, min: 1, max: 30 }
      focus:      { type: string,  default: "" }
      mode:       { type: enum, values: [strict, lenient], default: strict }
    roles:
      author:
        source: current
      reviewer:
        source: launch
        agents: [pi, codex]
        placement: split
        direction: right
    steps:
      - id: brief
        title: "Author writing the brief"
        message: author
        instruction: |
          Write a short brief for an adversarial reviewer: ## Scope, ## Claims.
          Focus: {{ inputs.focus }}
        expect: { output: brief, sections: ["## Scope", "## Claims"], timeout: 10m }
      - id: launch
        title: "Reviewer starting round 1"
        launch: reviewer
        prompt: "Read {{ outputs.brief.path }} and review ({{ inputs.mode }})."
        skill: prowl.adversarial-reviewer
        expect: { output: findings, sections: ["## Findings", "## Verdict"], verdict: [clean, issues] }
      - id: rounds
        repeat:
          max: "{{ inputs.max_rounds }}"
          until: outputs.findings.verdict == clean
        steps:
          - id: fix
            title: "Round {{ loop.index }}: author addressing findings"
            message: author
            text: "Findings: {{ outputs.findings.path }}. Fix or rebut each item."
            expect: { output: disposition }
          - id: rereview
            title: "Round {{ loop.index }}: reviewer re-checking"
            message: reviewer
            text: "Disposition: {{ outputs.disposition.path }}. Re-review."
            expect: { output: findings, verdict: [clean, issues] }
      - id: context
        action: git.context
        with: { root: "{{ worktree.path }}" }
      - id: done
        notify: "Adversarial review: {{ outputs.findings.verdict }} after {{ loop.count }} round(s)"
      - id: cleanup
        close: reviewer
    """

  nonisolated static let handoff = """
    schema: prowl.workflow/v1
    id: prowl.handoff
    name: Hand Off
    roles:
      source:
        source: current
      receiver:
        source: launch
        placement: tab
        background: true
    steps:
      - id: brief
        message: source
        instruction: |
          Write the handoff briefing.
        expect: { output: brief, sections: ["## Objective"] }
      - id: transition
        action: handoff.transition
        with: { briefing: "{{ outputs.brief.path }}", from: source, to: receiver }
      - id: launch
        launch: receiver
        prompt: "{{ actions.transition.kickoff_prompt }}"
      - id: done
        notify: "Handed off to {{ roles.receiver.name }}"
    """

  nonisolated static let authorPane = WorkflowPaneIdentity(
    surfaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    tabID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
    handle: "p1", displayName: "Claude Code", agent: "claude")
  nonisolated static let reviewerProfile = WorkflowProfileBinding(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, name: "Pi Reviewer", agent: "pi")
  nonisolated static let reviewerPane = WorkflowPaneIdentity(
    surfaceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    tabID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
    handle: "p2", displayName: "Pi Reviewer", agent: "pi")
  nonisolated static let runID = UUID(uuidString: "0BADCAFE-0000-4000-8000-000000000042")!
  nonisolated static let start = Date(timeIntervalSince1970: 1_760_000_000)

  nonisolated final class TokenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> String {
      lock.lock()
      defer { lock.unlock() }
      count += 1
      return "TOKEN-\(count)"
    }
  }

  private func definition(_ yaml: String) throws -> WorkflowDefinition {
    try #require(WorkflowDocumentParser.parse(yaml).definition)
  }

  private func makeMachine(
    _ yaml: String = adversarialReview,
    roles: [String: WorkflowRoleBinding]? = nil,
    inputs: [String: String] = [:],
    skipped: Set<String> = [],
    selfInitiated: Bool = false
  ) throws -> (WorkflowRunMachine, [WorkflowRunEffect]) {
    let counter = TokenCounter()
    let bindings =
      roles ?? [
        "author": .current(Self.authorPane),
        "reviewer": .launch(Self.reviewerProfile, pane: nil),
      ]
    let started = try WorkflowRunMachine.start(
      definition: definition(yaml),
      runID: Self.runID,
      context: WorkflowRunContext(
        scope: .repo(repositoryID: "repo-1"),
        definitionPath: "/repo/.prowl/workflows/review.yaml",
        worktree: WorkflowRunWorktree(id: "wt", name: "feature", branch: "feat/x", path: "/repo")),
      bindings: bindings,
      inputs: inputs,
      skippedSteps: skipped,
      selfInitiated: selfInitiated,
      now: { Self.start },
      makeToken: { counter.next() }
    )
    return (started.machine, started.effects)
  }

  private var runDir: String { "/repo/.prowl/workflow-runs/\(Self.runID.uuidString)" }

  /// Drives the fixture through `brief` → `launch` → findings delivery and returns the machine.
  private func machineAfterFindings(verdict: String, inputs: [String: String] = [:]) throws -> WorkflowRunMachine {
    var (machine, _) = try makeMachine(inputs: inputs)
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    let brief = machine.deliver(
      ordinal: 1, selector: .token("TOKEN-1"), body: "# Brief\n## Scope\nx\n## Claims\ny", verdict: nil)
    _ = try brief.result.get()
    _ = machine.apply(.launched(ordinal: 2, pane: Self.reviewerPane, dispatchID: "d2"))
    let findings = machine.deliver(
      ordinal: 2, selector: .token("TOKEN-2"), body: "## Findings\n- a\n## Verdict\n\(verdict)", verdict: verdict)
    _ = try findings.result.get()
    return machine
  }

  // MARK: - Linear flow

  @Test func startEntersTheFirstMessageStepByWaitingForTheRole() throws {
    let (machine, effects) = try makeMachine()
    #expect(machine.run.status == .running)
    #expect(machine.run.phase == .waitingForRole(role: "author", ordinal: 1))
    #expect(effects.contains(.awaitRoleIdle(role: "author", surfaceID: Self.authorPane.surfaceID, ordinal: 1)))
    #expect(effects.first == .log("Run \(Self.runID.uuidString) of workflow 'prowl.adversarial-review' started."))
    #expect(machine.run.invocations.map(\.ordinal) == [1])
    #expect(
      machine.run.stepRecords == [WorkflowStepRecord(stepID: "brief", iteration: nil, state: .active, ordinal: 1)])
    #expect(machine.run.inputs == ["max_rounds": "5", "focus": "", "mode": "strict"])
  }

  @Test func roleIdleMaterializesTheInstructionAndInjectsThePointerLineWithTheToken() throws {
    var (machine, _) = try makeMachine(inputs: ["focus": "the parser"])
    let effects = machine.apply(.roleIdle(ordinal: 1))
    let path = "\(runDir)/instructions/brief.1.md"
    let command = WorkflowCompletionCommand(token: "TOKEN-1", verdicts: nil)
    #expect(
      effects.contains(
        .materializeInstruction(
          ordinal: 1, stepID: "brief",
          text: "Write a short brief for an adversarial reviewer: ## Scope, ## Claims.\nFocus: the parser\n"
            + command.instructionTrailer())))
    #expect(
      effects.contains(
        .inject(
          role: "author", surfaceID: Self.authorPane.surfaceID, ordinal: 1,
          line: "[Prowl] Read \(path) and follow it — finish with: PROWL_WORKFLOW_TOKEN=TOKEN-1 prowl workflow done -",
          opensActivation: true)))
    #expect(machine.run.phase == .injecting(ordinal: 1))
    #expect(machine.run.invocations[0].activation?.token == "TOKEN-1")
    #expect(machine.run.invocations[0].instructionPath == path)
  }

  @Test func injectionSuccessOpensTheActivationAndArmsTheWatchdog() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    let effects = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    #expect(machine.run.phase == .waitingForDelivery(ordinal: 1))
    #expect(machine.run.activation(forDispatchID: "d1")?.ordinal == 1)
    #expect(machine.run.currentActivation?.state == .waiting)
    #expect(
      effects.contains(
        .armWatchdog(
          WorkflowWatchdogRequest(
            ordinal: 1, stepID: "brief", role: "author", surfaceID: Self.authorPane.surfaceID, dispatchID: "d1",
            timeoutSeconds: 600, timeoutPolicy: .attention, nudgedAlready: false))))
  }

  @Test func deliveryChecksTheTokenValidatesTheBodyAndAdvancesToTheLaunch() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))

    #expect(
      machine.deliver(ordinal: 1, selector: .token(nil), body: "x", verdict: nil).result == .failure(.tokenRequired))
    #expect(
      machine.deliver(ordinal: 1, selector: .token("nope"), body: "x", verdict: nil).result == .failure(.tokenInvalid))
    #expect(
      machine.deliver(ordinal: 2, selector: .token("TOKEN-1"), body: "x", verdict: nil).result
        == .failure(.stepNotExpecting))
    let invalid = machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope only", verdict: nil)
    #expect(invalid.result.failureCode == "OUTPUT_INVALID")
    #expect(machine.run.phase == .waitingForDelivery(ordinal: 1))

    let (result, effects) = machine.deliver(
      ordinal: 1, selector: .token("TOKEN-1"), body: "```md\n# Brief\n## Scope\nx\n## Claims\ny\n```", verdict: nil)
    let receipt = try result.get()
    #expect(receipt.output.name == "brief")
    #expect(receipt.output.path == "\(runDir)/outputs/brief.1.md")
    #expect(receipt.output.latestPath == "\(runDir)/outputs/brief.md")
    #expect(effects.contains(.persistOutput(name: "brief", ordinal: 1, body: "# Brief\n## Scope\nx\n## Claims\ny\n")))
    #expect(effects.contains(.disarmWatchdog(ordinal: 1)))
    #expect(
      effects.contains(
        .completeActivation(dispatchID: "d1", summary: "Delivered output 'brief' for workflow step 'brief'.")))
    #expect(effects.contains(.materializeSkill(id: "prowl.adversarial-reviewer")))
    guard
      case .launch(let request)? = effects.first(where: { if case .launch = $0 { return true } else { return false } })
    else {
      Issue.record("expected a launch effect")
      return
    }
    #expect(request.role == "reviewer")
    #expect(request.ordinal == 2)
    #expect(request.profile == Self.reviewerProfile)
    #expect(
      request.prompt.hasPrefix(
        "Read \(runDir)/outputs/brief.md and review (strict).\n\n---\nProwl workflow completion protocol v1:"))
    #expect(
      request.prompt.contains("\nprowl workflow done --verdict clean -\nor:\nprowl workflow done --verdict issues -\n"))
    #expect(request.prompt.contains("Reviewer starting round 1"))
    #expect(
      request.environment == [
        "PROWL_WORKFLOW_TOKEN": "TOKEN-2", "PROWL_WORKFLOW_RUN": Self.runID.uuidString,
        "PROWL_WORKFLOW_ROLE": "reviewer",
      ])
    #expect(request.placement == .split)
    #expect(request.direction == .right)
    #expect(request.anchorSurfaceID == Self.authorPane.surfaceID)
    #expect(request.expectsDelivery)
    #expect(!request.redelivery)
    #expect(machine.run.phase == .launching(ordinal: 2))
    #expect(machine.run.invocations[0].activation?.state == .delivered)
    #expect(machine.run.outputs["brief"]?.ordinal == 1)
  }

  @Test func launchedBindsThePaneAndWaitsForTheFindings() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope\nx\n## Claims\ny", verdict: nil)
    let effects = machine.apply(.launched(ordinal: 2, pane: Self.reviewerPane, dispatchID: "d2"))
    #expect(machine.run.bindings["reviewer"]?.pane == Self.reviewerPane)
    #expect(machine.run.phase == .waitingForDelivery(ordinal: 2))
    #expect(machine.run.activation(forDispatchID: "d2")?.token == "TOKEN-2")
    #expect(
      effects.contains {
        if case .armWatchdog(let request) = $0 {
          return request.ordinal == 2 && request.dispatchID == "d2"
        } else {
          return false
        }
      })
    #expect(machine.templateContext().roles["reviewer"]?.pane == "p2")
  }

  @Test func verdictRequiredAndUndeclaredVerdictAreRejected() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope\nx\n## Claims\ny", verdict: nil)
    _ = machine.apply(.launched(ordinal: 2, pane: Self.reviewerPane, dispatchID: "d2"))
    #expect(
      machine.deliver(ordinal: 2, selector: .token("TOKEN-2"), body: "## Findings\n## Verdict", verdict: nil).result
        == .failure(.verdictRequired(allowed: ["clean", "issues"])))
    #expect(
      machine.deliver(ordinal: 2, selector: .token("TOKEN-2"), body: "## Findings\n## Verdict", verdict: "maybe").result
        .failureCode == "OUTPUT_INVALID")
  }

  @Test func cleanVerdictBeforeTheLoopSkipsItAndFinishesTheRun() throws {
    var machine = try machineAfterFindings(verdict: "clean")
    #expect(machine.run.loopCount == 0)
    #expect(machine.run.phase == .runningAction(stepID: "context"))
    #expect(
      machine.run.stepRecords.contains(
        WorkflowStepRecord(stepID: "rounds", iteration: nil, state: .skipped, ordinal: nil)))
    let effects = machine.apply(
      .actionCompleted(stepID: "context", outputs: ["path": "/repo/.prowl/handoff/context.md", "branch": "feat/x"]))
    #expect(effects.contains(.notify("Adversarial review: clean after 0 round(s)")))
    #expect(effects.contains(.close(role: "reviewer", surfaceID: Self.reviewerPane.surfaceID)))
    #expect(effects.last == .finished(.completed))
    #expect(machine.run.status == .completed)
    #expect(machine.run.finishedAt == Self.start)
    #expect(machine.run.actionOutputs["context"]?["branch"] == "feat/x")
  }

  @Test func issuesVerdictRunsRoundsUntilCleanWithLatestWinsOutputs() throws {
    var machine = try machineAfterFindings(verdict: "issues", inputs: ["max_rounds": "3"])
    #expect(machine.run.position.loop == WorkflowRunPosition.Loop(iteration: 1, bodyIndex: 0, max: 3))
    #expect(machine.run.phase == .waitingForRole(role: "author", ordinal: 3))
    #expect(machine.run.stepRecords.last == WorkflowStepRecord(stepID: "fix", iteration: 1, state: .active, ordinal: 3))

    let inject = machine.apply(.roleIdle(ordinal: 3))
    #expect(
      inject.contains(
        .inject(
          role: "author", surfaceID: Self.authorPane.surfaceID, ordinal: 3,
          line: "[Prowl] Findings: \(runDir)/outputs/findings.md. Fix or rebut each item. — finish with: "
            + "PROWL_WORKFLOW_TOKEN=TOKEN-3 prowl workflow done -",
          opensActivation: true)))
    _ = machine.apply(.injectionSucceeded(ordinal: 3, dispatchID: "d3"))
    _ = try machine.deliver(ordinal: 3, selector: .token("TOKEN-3"), body: "# Done\nfixed", verdict: nil).result.get()

    #expect(machine.run.phase == .waitingForRole(role: "reviewer", ordinal: 4))
    _ = machine.apply(.roleIdle(ordinal: 4))
    _ = machine.apply(.injectionSucceeded(ordinal: 4, dispatchID: "d4"))
    let round1 = machine.deliver(ordinal: 4, selector: .token("TOKEN-4"), body: "# Findings\nstill", verdict: "issues")
    let receipt = try round1.result.get()
    #expect(receipt.output.path == "\(runDir)/outputs/findings.4.md")
    #expect(round1.effects.contains(.persistOutput(name: "findings", ordinal: 4, body: "# Findings\nstill\n")))
    #expect(machine.run.outputs["findings"]?.ordinal == 4)
    #expect(machine.run.loopCount == 1)
    #expect(machine.run.position.loop == WorkflowRunPosition.Loop(iteration: 2, bodyIndex: 0, max: 3))
    #expect(machine.templateContext().loop == WorkflowTemplateContext.Loop(index: 2, count: 1))

    _ = machine.apply(.roleIdle(ordinal: 5))
    _ = machine.apply(.injectionSucceeded(ordinal: 5, dispatchID: "d5"))
    _ = try machine.deliver(ordinal: 5, selector: .token("TOKEN-5"), body: "# Done\nfixed again", verdict: nil).result
      .get()
    _ = machine.apply(.roleIdle(ordinal: 6))
    _ = machine.apply(.injectionSucceeded(ordinal: 6, dispatchID: "d6"))
    _ = try machine.deliver(ordinal: 6, selector: .token("TOKEN-6"), body: "# Findings\nnone", verdict: "clean").result
      .get()
    #expect(machine.run.loopCount == 2)
    #expect(machine.run.position.loop == nil)
    #expect(machine.run.phase == .runningAction(stepID: "context"))
    let effects = machine.apply(.actionCompleted(stepID: "context", outputs: [:]))
    #expect(effects.contains(.notify("Adversarial review: clean after 2 round(s)")))
    #expect(machine.run.status == .completed)
  }

  @Test func reachingMaxWithIssuesEndsAsMaxRoundsReached() throws {
    var machine = try machineAfterFindings(verdict: "issues", inputs: ["max_rounds": "1"])
    _ = machine.apply(.roleIdle(ordinal: 3))
    _ = machine.apply(.injectionSucceeded(ordinal: 3, dispatchID: "d3"))
    _ = try machine.deliver(ordinal: 3, selector: .token("TOKEN-3"), body: "# Done", verdict: nil).result.get()
    _ = machine.apply(.roleIdle(ordinal: 4))
    _ = machine.apply(.injectionSucceeded(ordinal: 4, dispatchID: "d4"))
    let (result, effects) = machine.deliver(
      ordinal: 4, selector: .token("TOKEN-4"), body: "# Findings", verdict: "issues")
    _ = try result.get()
    #expect(machine.run.status == .maxRoundsReached)
    #expect(effects.last == .finished(.maxRoundsReached))
    #expect(machine.run.loopCount == 1)
  }

  // MARK: - Start validation

  @Test func startValidatesInputsRepeatBoundsPathAndBindings() throws {
    #expect(throws: WorkflowRunStartError.invalidRepeatBound(step: "rounds")) {
      try makeMachine(inputs: ["max_rounds": "25"])
    }
    #expect(throws: WorkflowRunStartError.invalidInput(name: "max_rounds", reason: "40 is above the maximum 30.")) {
      try makeMachine(inputs: ["max_rounds": "40"])
    }
    #expect(
      throws: WorkflowRunStartError.invalidInput(
        name: "focus", reason: "the value must be one line without control characters.")
    ) {
      try makeMachine(inputs: ["focus": "a\nb"])
    }
    #expect(throws: WorkflowRunStartError.invalidInput(name: "mode", reason: "'loose' is not one of strict, lenient."))
    {
      try makeMachine(inputs: ["mode": "loose"])
    }
    #expect(
      throws: WorkflowRunStartError.invalidInput(name: "other", reason: "the workflow declares no input 'other'.")
    ) {
      try makeMachine(inputs: ["other": "1"])
    }
    #expect(throws: WorkflowRunStartError.missingBinding(role: "reviewer")) {
      try makeMachine(roles: ["author": .current(Self.authorPane)])
    }
    #expect(throws: WorkflowRunStartError.unknownSkipStep("nope")) {
      try makeMachine(skipped: ["nope"])
    }
    #expect(throws: WorkflowRunStartError.skipNotAllowed(step: "brief", dependent: "launch")) {
      try makeMachine(skipped: ["brief"])
    }
  }

  @Test func startRejectsAWorktreePathThatIsNotOneLine() throws {
    #expect(throws: WorkflowRunStartError.unsafePath("/re\npo")) {
      try WorkflowRunMachine.start(
        definition: definition(Self.handoff),
        runID: Self.runID,
        context: WorkflowRunContext(
          scope: .user, definitionPath: nil,
          worktree: WorkflowRunWorktree(id: "wt", name: "w", branch: "b", path: "/re\npo")),
        bindings: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)],
        inputs: [:],
        now: { Self.start })
    }
  }

  // MARK: - Skip rule

  @Test func skipWithANonOptionalConsumerEndsTheRunAndAbandonsTheActivation() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    #expect(machine.skipConsequence(forStep: "brief") == .endsRun(dependent: "launch"))
    let effects = machine.apply(.user(.skip))
    #expect(machine.run.status == .skipped(step: "brief", dependent: "launch"))
    #expect(
      effects.contains(
        .abandonActivation(dispatchID: "d1", reason: "Workflow run \(Self.runID.uuidString): step 'brief' skipped.")))
    #expect(effects.contains(.disarmWatchdog(ordinal: 1)))
    #expect(effects.last == .finished(.skipped(step: "brief", dependent: "launch")))
    #expect(machine.run.invocations[0].activation?.state == .skipped)
    #expect(
      machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "x", verdict: nil).result
        == .failure(.stepNotExpecting))
  }

  @Test func skipInsideTheLoopEndsTheRunBecauseUntilReadsTheOutput() throws {
    var machine = try machineAfterFindings(verdict: "issues")
    _ = machine.apply(.roleIdle(ordinal: 3))
    _ = machine.apply(.injectionSucceeded(ordinal: 3, dispatchID: "d3"))
    _ = try machine.deliver(ordinal: 3, selector: .token("TOKEN-3"), body: "# Done", verdict: nil).result.get()
    #expect(machine.skipConsequence(forStep: "rereview") == .endsRun(dependent: "rounds"))
    #expect(machine.skipConsequence(forStep: "fix") == .endsRun(dependent: "rereview"))
    _ = machine.apply(.roleIdle(ordinal: 4))
    _ = machine.apply(.injectionSucceeded(ordinal: 4, dispatchID: "d4"))
    _ = machine.apply(.user(.skip))
    #expect(machine.run.status == .skipped(step: "rereview", dependent: "rounds"))
  }

  @Test func skipOfAnOptionalActionInputContinuesWithoutTheKey() throws {
    var (machine, _) = try makeMachine(
      Self.handoff,
      roles: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)])
    #expect(machine.skipConsequence(forStep: "brief") == .continues(optionalInputs: ["transition"]))
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    let effects = machine.apply(.user(.skip))
    #expect(machine.run.status == .running)
    #expect(machine.run.skippedOutputs == ["brief": "brief"])
    #expect(
      effects.contains(
        .runAction(stepID: "transition", actionID: "handoff.transition", inputs: ["from": "source", "to": "receiver"])))
    #expect(machine.run.phase == .runningAction(stepID: "transition"))
    let launch = machine.apply(
      .actionCompleted(
        stepID: "transition", outputs: ["kickoff_prompt": "Take over.", "artifact_path": "/x", "has_briefing": "false"])
    )
    guard
      case .launch(let request)? = launch.first(where: { if case .launch = $0 { return true } else { return false } })
    else {
      Issue.record("expected a launch effect")
      return
    }
    #expect(request.prompt == "Take over.")
    #expect(!request.expectsDelivery)
    #expect(request.environment == ["PROWL_WORKFLOW_RUN": Self.runID.uuidString, "PROWL_WORKFLOW_ROLE": "receiver"])
    #expect(request.placement == .tab)
    #expect(request.background)
    let done = machine.apply(.launched(ordinal: 2, pane: Self.reviewerPane, dispatchID: nil))
    #expect(done.contains(.notify("Handed off to Pi Reviewer")))
    #expect(machine.run.status == .completed)
  }

  @Test func preSkippedStepsAreRecordedSkippedAndNeverEntered() throws {
    let (machine, effects) = try makeMachine(
      Self.handoff,
      roles: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)],
      skipped: ["brief"])
    #expect(
      machine.run.stepRecords.first
        == WorkflowStepRecord(stepID: "brief", iteration: nil, state: .skipped, ordinal: nil))
    #expect(machine.run.invocations.isEmpty)
    #expect(
      effects.contains(
        .runAction(stepID: "transition", actionID: "handoff.transition", inputs: ["from": "source", "to": "receiver"])))
    #expect(!machine.run.deliversToCurrentRole())
    let (unskipped, _) = try makeMachine(
      Self.handoff, roles: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)])
    #expect(unskipped.run.deliversToCurrentRole())
  }

  // MARK: - Attention, retry, relaunch, cancel

  @Test func injectionFailureRaisesAttentionAndRetryMintsANewInvocation() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionFailed(ordinal: 1, .submitFailed))
    let attention = try #require(machine.run.status.attention)
    #expect(attention.reason == .injectionFailed(.submitFailed))
    #expect(attention.actions == [.focusPane, .retry, .skip, .cancel])
    #expect(attention.message.contains("unsubmitted"))
    #expect(attention.message.contains("author (Claude Code)"))
    #expect(machine.run.activation(forDispatchID: "d1") == nil)

    let effects = machine.apply(.user(.retry))
    #expect(machine.run.status == .running)
    #expect(machine.run.phase == .waitingForRole(role: "author", ordinal: 2))
    #expect(effects.contains(.awaitRoleIdle(role: "author", surfaceID: Self.authorPane.surfaceID, ordinal: 2)))
    #expect(machine.run.invocations[0].activation?.state == .revoked)
    #expect(machine.run.stepRecords.map(\.state) == [.failed, .active])
    _ = machine.apply(.roleIdle(ordinal: 2))
    #expect(machine.run.invocations[1].activation?.token == "TOKEN-2")
  }

  @Test func roleBusyReturnsTheStepToItsIdleWait() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    let effects = machine.apply(.injectionFailed(ordinal: 1, .roleBusy))
    #expect(machine.run.status == .running)
    #expect(machine.run.phase == .waitingForRole(role: "author", ordinal: 1))
    #expect(effects.contains(.awaitRoleIdle(role: "author", surfaceID: Self.authorPane.surfaceID, ordinal: 1)))
  }

  @Test func skipDuringTheIdleWaitCancelsTheWait() throws {
    var (machine, _) = try makeMachine(
      Self.handoff,
      roles: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)])
    let effects = machine.apply(.user(.skip))
    #expect(effects.contains(.cancelRoleWait(ordinal: 1)))
    #expect(machine.run.phase == .runningAction(stepID: "transition"))
  }

  @Test func watchdogNudgeTypesTheNudgeAndAttentionOffersTheIdleActions() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    let nudge = machine.apply(.watchdog(ordinal: 1, .nudge))
    let command = WorkflowCompletionCommand(token: "TOKEN-1", verdicts: nil)
    #expect(
      nudge.contains(
        .typeLine(
          role: "author", surfaceID: Self.authorPane.surfaceID, line: try WorkflowTypedLine.nudge(completion: command)))
    )
    #expect(machine.run.status == .running)

    #expect(machine.apply(.watchdog(ordinal: 7, .attention(.idleWithoutDelivery))).isEmpty)
    _ = machine.apply(.watchdog(ordinal: 1, .attention(.idleWithoutDelivery)))
    let attention = try #require(machine.run.status.attention)
    #expect(attention.reason == .idleWithoutDelivery)
    #expect(attention.actions == [.nudge, .keepWaiting, .skip, .cancel])
    #expect(attention.message == "author (Claude Code) has been idle without delivering brief; Prowl nudged it once.")

    let resumed = machine.apply(.user(.keepWaiting))
    #expect(machine.run.status == .running)
    #expect(
      resumed.contains(
        .armWatchdog(
          WorkflowWatchdogRequest(
            ordinal: 1, stepID: "brief", role: "author", surfaceID: Self.authorPane.surfaceID, dispatchID: "d1",
            timeoutSeconds: 600, timeoutPolicy: .attention, nudgedAlready: true))))

    _ = machine.apply(.watchdog(ordinal: 1, .attention(.needsInput)))
    #expect(machine.run.status.attention?.actions == [.focusPane, .cancel])
    let late = machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope\nx\n## Claims\ny", verdict: nil)
    #expect((try? late.result.get()) != nil)
    #expect(machine.run.status == .running)
    #expect(machine.run.phase == .launching(ordinal: 2))
  }

  @Test func userNudgeTypesAgainAndReArmsWithTheNudgeSpent() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = machine.apply(.watchdog(ordinal: 1, .attention(.idleWithoutDelivery)))
    let effects = machine.apply(.user(.nudge))
    #expect(effects.contains { if case .typeLine = $0 { return true } else { return false } })
    #expect(
      effects.contains { if case .armWatchdog(let request) = $0 { return request.nudgedAlready } else { return false } }
    )
    #expect(machine.run.status == .running)
  }

  @Test func timeoutPoliciesAttentionSkipAndCancel() throws {
    var attention = try makeMachine().0
    _ = attention.apply(.roleIdle(ordinal: 1))
    _ = attention.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = attention.apply(.watchdog(ordinal: 1, .timeout))
    #expect(attention.run.status.attention?.reason == .timeout)
    #expect(attention.run.status.attention?.actions == [.nudge, .keepWaiting, .skip, .cancel])

    let skipYAML = Self.handoff.replacing(
      "expect: { output: brief, sections: [\"## Objective\"] }",
      with: "expect: { output: brief, timeout: 1m, on_timeout: skip }")
    var skipping = try makeMachine(
      skipYAML, roles: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)]
    ).0
    _ = skipping.apply(.roleIdle(ordinal: 1))
    _ = skipping.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    let skipped = skipping.apply(.watchdog(ordinal: 1, .timeout))
    #expect(
      skipped.contains(
        .abandonActivation(dispatchID: "d1", reason: "Workflow run \(Self.runID.uuidString): step 'brief' skipped.")))
    #expect(skipping.run.phase == .runningAction(stepID: "transition"))

    let cancelYAML = Self.handoff.replacing(
      "expect: { output: brief, sections: [\"## Objective\"] }",
      with: "expect: { output: brief, timeout: 1m, on_timeout: cancel }")
    var cancelling = try makeMachine(
      cancelYAML, roles: ["source": .current(Self.authorPane), "receiver": .launch(Self.reviewerProfile, pane: nil)]
    ).0
    _ = cancelling.apply(.roleIdle(ordinal: 1))
    _ = cancelling.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = cancelling.apply(.watchdog(ordinal: 1, .timeout))
    #expect(cancelling.run.status == .cancelled)
  }

  @Test func cancelAbandonsTheActivationNamingRunAndStepAndKeepsOutputs() throws {
    var machine = try machineAfterFindings(verdict: "issues")
    _ = machine.apply(.roleIdle(ordinal: 3))
    _ = machine.apply(.injectionSucceeded(ordinal: 3, dispatchID: "d3"))
    let effects = machine.apply(.user(.cancel))
    #expect(machine.run.status == .cancelled)
    #expect(
      effects.contains(
        .abandonActivation(dispatchID: "d3", reason: "Workflow run \(Self.runID.uuidString) cancelled at step 'fix'.")))
    #expect(effects.contains(.disarmWatchdog(ordinal: 3)))
    #expect(effects.last == .finished(.cancelled))
    #expect(machine.run.outputs.keys.sorted() == ["brief", "findings"])
    #expect(!effects.contains { if case .close = $0 { return true } else { return false } })
    #expect(machine.apply(.user(.retry)).isEmpty)
  }

  @Test func relaunchRedeliversTheCurrentStepAsALaunchPromptAndRebindsThePane() throws {
    var machine = try machineAfterFindings(verdict: "issues")
    _ = machine.apply(.roleIdle(ordinal: 3))
    _ = machine.apply(.injectionSucceeded(ordinal: 3, dispatchID: "d3"))
    _ = try machine.deliver(ordinal: 3, selector: .token("TOKEN-3"), body: "# Done", verdict: nil).result.get()
    _ = machine.apply(.roleIdle(ordinal: 4))
    _ = machine.apply(.injectionSucceeded(ordinal: 4, dispatchID: "d4"))
    _ = machine.apply(.watchdog(ordinal: 4, .attention(.agentGone(.sessionEnded))))
    let attention = try #require(machine.run.status.attention)
    #expect(attention.actions == [.relaunch, .skip, .cancel])
    #expect(attention.message == "reviewer (Pi Reviewer)'s agent session ended before it delivered findings.")

    let effects = machine.apply(.user(.relaunch))
    #expect(
      effects.contains(
        .abandonActivation(
          dispatchID: "d4",
          reason: "Workflow run \(Self.runID.uuidString): role 'reviewer' relaunched at step 'rereview'.")))
    guard
      case .launch(let request)? = effects.first(where: { if case .launch = $0 { return true } else { return false } })
    else {
      Issue.record("expected a launch effect")
      return
    }
    #expect(request.redelivery)
    #expect(request.ordinal == 5)
    #expect(
      request.prompt.hasPrefix(
        "Disposition: \(runDir)/outputs/disposition.md. Re-review.\n\n---\nProwl workflow completion protocol v1:"))
    #expect(request.environment["PROWL_WORKFLOW_TOKEN"] == "TOKEN-5")
    #expect(machine.run.bindings["reviewer"]?.pane == nil)
    #expect(machine.run.invocations[3].activation?.state == .revoked)

    let newPane = WorkflowPaneIdentity(
      surfaceID: UUID(), tabID: nil, handle: "p5", displayName: "Pi Reviewer", agent: "pi")
    _ = machine.apply(.launched(ordinal: 5, pane: newPane, dispatchID: "d5"))
    #expect(machine.run.bindings["reviewer"]?.pane == newPane)
    #expect(machine.run.phase == .waitingForDelivery(ordinal: 5))
    #expect(
      machine.deliver(ordinal: 4, selector: .token("TOKEN-4"), body: "# Findings", verdict: "clean").result
        == .failure(.stepNotExpecting))
    _ = try machine.deliver(ordinal: 5, selector: .token("TOKEN-5"), body: "# Findings", verdict: "clean").result.get()
    #expect(machine.run.position.loop == nil)
  }

  @Test func aGoneCurrentRoleOffersNoRelaunch() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = machine.apply(.watchdog(ordinal: 1, .attention(.agentGone(.paneClosed))))
    #expect(machine.run.status.attention?.actions == [.skip, .cancel])
    #expect(machine.apply(.user(.relaunch)).isEmpty)
  }

  @Test func launchFailureThenSkipLeavesTheRoleWithoutAPane() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    _ = try machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope\nx\n## Claims\ny", verdict: nil)
      .result.get()
    _ = machine.apply(.launchFailed(ordinal: 2, reason: "home provisioning failed"))
    let attention = try #require(machine.run.status.attention)
    #expect(attention.reason == .launchFailed("home provisioning failed"))
    #expect(attention.actions == [.retry, .skip, .cancel])
    let retry = machine.apply(.user(.retry))
    #expect(
      retry.contains {
        if case .launch(let request) = $0 {
          return request.ordinal == 3 && request.environment["PROWL_WORKFLOW_TOKEN"] == "TOKEN-3"
        } else {
          return false
        }
      })
    _ = machine.apply(.launchFailed(ordinal: 3, reason: "again"))
    #expect(machine.skipConsequence(forStep: "launch") == .endsRun(dependent: "rounds"))
    _ = machine.apply(.user(.skip))
    #expect(machine.run.status == .skipped(step: "launch", dependent: "rounds"))
  }

  @Test func actionFailureOffersRetryAndCancelOnly() throws {
    var machine = try machineAfterFindings(verdict: "clean")
    _ = machine.apply(.actionFailed(stepID: "context", reason: "git is unavailable"))
    let attention = try #require(machine.run.status.attention)
    #expect(attention.reason == .actionFailed("git is unavailable"))
    #expect(attention.actions == [.retry, .cancel])
    #expect(machine.apply(.user(.skip)).isEmpty)
    let retry = machine.apply(.user(.retry))
    #expect(retry.contains(.runAction(stepID: "context", actionID: "git.context", inputs: ["root": "/repo"])))
    #expect(machine.run.status == .running)
  }

  @Test func manualDeliveryTargetsTheStepsCurrentActivation() throws {
    var (machine, _) = try makeMachine()
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    #expect(
      machine.deliver(ordinal: nil, selector: .manual(stepID: "launch"), body: "x", verdict: nil).result
        == .failure(.stepNotExpecting))
    let (result, _) = machine.deliver(
      ordinal: nil, selector: .manual(stepID: "brief"), body: "## Scope\nx\n## Claims\ny", verdict: nil)
    #expect(try result.get().stepID == "brief")
  }

  @Test func selfInitiatedRunReturnsTheFirstLineInsteadOfTyping() throws {
    let (machine, effects) = try makeMachine(selfInitiated: true)
    #expect(effects.contains(.openActivation(role: "author", surfaceID: Self.authorPane.surfaceID, ordinal: 1)))
    #expect(!effects.contains { if case .inject = $0 { return true } else { return false } })
    #expect(!effects.contains { if case .awaitRoleIdle = $0 { return true } else { return false } })
    let line = try #require(machine.run.selfInitiatedLine)
    #expect(
      line.hasPrefix(
        "[Prowl] Read \(runDir)/instructions/brief.1.md and follow it — finish with: PROWL_WORKFLOW_TOKEN=TOKEN-1"))
    #expect(machine.run.phase == .injecting(ordinal: 1))
    var continued = machine
    _ = continued.apply(.injectionSucceeded(ordinal: 1, dispatchID: "d1"))
    #expect(continued.run.phase == .waitingForDelivery(ordinal: 1))
  }

  @Test func messageToARoleWithoutAPaneRaisesAttention() throws {
    let yaml = """
      schema: prowl.workflow/v1
      id: ping
      name: Ping
      roles:
        author:
          source: current
        reviewer:
          source: launch
      steps:
        - id: launch
          launch: reviewer
          prompt: "Review."
        - id: ping
          message: reviewer
          text: "hello"
          expect: { output: pong }
      """
    var (machine, _) = try makeMachine(yaml, skipped: ["launch"])
    #expect(machine.run.phase == .injecting(ordinal: 1))
    let attention = try #require(machine.run.status.attention)
    #expect(attention.reason == .agentGone(.notLaunched))
    #expect(attention.actions == [.relaunch, .skip, .cancel])
    let effects = machine.apply(.user(.relaunch))
    #expect(
      effects.contains {
        if case .launch(let request) = $0 {
          return request.redelivery && request.prompt.hasPrefix("hello\n\n---\n")
        } else {
          return false
        }
      })
  }
}
// swiftlint:enable file_length type_body_length

extension Result where Failure == WorkflowDeliveryError {
  var failureCode: String? {
    if case .failure(let error) = self { return error.code }
    return nil
  }
}
