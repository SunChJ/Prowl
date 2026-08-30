// supacodeTests/WorkflowRuntimeCoordinatorTests.swift
// `prowl workflow status / done / cancel` attribution and responses (docs-ai 063 B3, W1/W3/W5).

import Foundation
import Testing

@testable import supacode

@MainActor
struct WorkflowRuntimeCoordinatorTests {
  nonisolated private static let now = Date(timeIntervalSince1970: 1_760_000_000)

  @MainActor
  final class Fixture {
    let root: URL
    var sessions: [WorkflowRunSession] = []
    var sent: [WorkflowRunsFeature.Action] = []
    var pendingByPane: [UUID: String] = [:]
    let rendezvous = WorkflowCLIRendezvous()
    let requestID = UUID()
    /// What the reducer would answer to a `.deliver`, applied synchronously inside `send`.
    var answer: WorkflowDeliveryResolution?
    private(set) var coordinator: WorkflowRuntimeCoordinator!

    init() throws {
      root =
        FileManager.default.temporaryDirectory
        .appending(path: "workflow-coordinator-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .standardizedFileURL
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      coordinator = WorkflowRuntimeCoordinator(
        dependencies: WorkflowRuntimeCoordinator.Dependencies(
          admissionEnvironment: { fatalError("admission is covered by WorkflowRunAdmissionTests") },
          sessions: { [self] in sessions },
          send: { [self] action in
            sent.append(action)
            if case .deliver(let request) = action, let answer {
              coordinator.resolve(request.requestID, answer)
            }
            if case .userAction(let runID, .cancel) = action,
              let index = sessions.firstIndex(where: { $0.run.id == runID })
            {
              var machine = sessions[index].machine(now: { WorkflowRuntimeCoordinatorTests.now }, makeToken: { "T" })
              _ = machine.apply(.user(.cancel))
              sessions[index].run = machine.run
            }
          },
          pendingDispatchID: { [self] surfaceID in pendingByPane[surfaceID] },
          worktreeRoots: { [self] in [root] },
          rendezvous: rendezvous,
          makeRequestID: { [self] in requestID }))
    }

    func cleanUp() {
      try? FileManager.default.removeItem(at: root)
    }

    /// A review run whose first activation (`brief`, ordinal 1) waits on `dispatch-1` in the author pane.
    func waitingSession() throws -> WorkflowRunSession {
      let definition = try #require(WorkflowDocumentParser.parse(WorkflowRunMachineTests.adversarialReview).definition)
      let counter = WorkflowRunMachineTests.TokenCounter()
      let started = try WorkflowRunMachine.start(
        WorkflowRunStartRequest(
          definition: definition,
          runID: UUID(),
          context: WorkflowRunContext(
            scope: .user, definitionPath: nil,
            worktree: WorkflowRunWorktree(
              id: "wt", name: "feature", branch: "feat/x", path: root.path(percentEncoded: false))),
          bindings: [
            "author": .current(WorkflowRunMachineTests.authorPane),
            "reviewer": .launch(WorkflowRunMachineTests.reviewerProfile, pane: nil),
          ]),
        now: { WorkflowRuntimeCoordinatorTests.now },
        makeToken: { counter.next() })
      var machine = started.machine
      _ = machine.apply(.roleIdle(ordinal: 1))
      _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "dispatch-1"))
      pendingByPane[WorkflowRunMachineTests.authorPane.surfaceID] = "dispatch-1"
      return WorkflowRunSession(
        run: machine.run,
        worktree: Worktree(id: "wt", name: "feature", detail: "", workingDirectory: root, repositoryRootURL: root),
        launchPlans: [:])
    }
  }

  private static let authorCaller = CallerPane(
    worktreeID: "wt", surfaceID: WorkflowRunMachineTests.authorPane.surfaceID)
  private static let strangerCaller = CallerPane(worktreeID: "wt", surfaceID: UUID())

  private func delivered(_ session: WorkflowRunSession) throws -> WorkflowDeliveryResolution {
    var machine = session.machine(now: { Self.now }, makeToken: { "T" })
    let (result, _) = machine.deliver(
      ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope\nx\n## Claims\ny", verdict: nil)
    _ = machine.apply(.outputPersisted(ordinal: 1))
    return .delivered(run: machine.run, receipt: try result.get())
  }

  private func payload(_ response: CommandResponse) throws -> WorkflowCommandPayload {
    try JSONDecoder().decode(WorkflowCommandPayload.self, from: try #require(response.data).bytes)
  }

  // MARK: - done attribution (decision W3)

  @Test func doneFromTheRolePaneIsAttributedByItsPendingDispatch() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]
    fixture.answer = try delivered(session)

    let response = await fixture.coordinator.done(
      WorkflowInput(action: .done, body: "## Scope\nx\n## Claims\ny", token: "TOKEN-1"), callerPane: Self.authorCaller)
    #expect(response.ok, "\(response.error?.message ?? "")")
    guard case .deliver(let request) = fixture.sent.first else {
      Issue.record("expected a deliver action")
      return
    }
    #expect(request.requestID == fixture.requestID)
    #expect(request.runID == session.run.id)
    #expect(request.ordinal == 1)
    #expect(request.selector == .token("TOKEN-1"))
    #expect(request.source == "pane")
    #expect(request.body == "## Scope\nx\n## Claims\ny")
    guard case .done(let done) = try payload(response) else {
      Issue.record("expected a done payload")
      return
    }
    #expect(done.delivery.state == .delivered)
    #expect(done.delivery.role == "author")
    #expect(done.delivery.output.name == "brief")
    #expect(done.run.role == "author")
    #expect(fixture.rendezvous.pendingRequestIDs.isEmpty)
  }

  @Test func doneWithoutABodyOrHalfAManualTargetIsInvalid() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let noBody = await fixture.coordinator.done(WorkflowInput(action: .done), callerPane: Self.authorCaller)
    #expect(noBody.error?.code == CLIErrorCode.invalidArgument)
    let half = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: UUID().uuidString, body: "x"), callerPane: Self.authorCaller)
    #expect(half.error?.code == CLIErrorCode.invalidArgument)
    let badID = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: "nope", stepID: "brief", body: "x"), callerPane: nil)
    #expect(badID.error?.code == CLIErrorCode.invalidArgument)
    #expect(fixture.sent.isEmpty)
  }

  @Test func doneOutsideAnyPaneNeedsAnExplicitTargetAndThenIsManual() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]
    fixture.answer = .failed(code: CLIErrorCode.stepNotExpecting, message: "no")

    let missing = await fixture.coordinator.done(WorkflowInput(action: .done, body: "x"), callerPane: nil)
    #expect(missing.error?.code == CLIErrorCode.sourceRequired)
    #expect(fixture.sent.isEmpty)

    let manual = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: session.run.id.uuidString, stepID: "brief", body: "x"), callerPane: nil)
    #expect(manual.error?.code == CLIErrorCode.stepNotExpecting, "the reducer's answer is passed through")
    guard case .deliver(let request) = fixture.sent.first else {
      Issue.record("expected a deliver action")
      return
    }
    #expect(request.ordinal == nil)
    #expect(request.selector == .manual(stepID: "brief"))
    #expect(request.source == "manual")

    let unknown = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: UUID().uuidString, stepID: "brief", body: "x"), callerPane: nil)
    #expect(unknown.error?.code == CLIErrorCode.runNotFound)
  }

  @Test func aPaneWithoutAnActivationCanStillDeliverManuallyButNotImplicitly() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]
    fixture.answer = .failed(code: CLIErrorCode.stepNotExpecting, message: "no")

    let implicit = await fixture.coordinator.done(
      WorkflowInput(action: .done, body: "x"), callerPane: Self.strangerCaller)
    #expect(implicit.error?.code == CLIErrorCode.stepNotExpecting)
    #expect(fixture.sent.isEmpty)

    _ = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: session.run.id.uuidString, stepID: "brief", body: "x"),
      callerPane: Self.strangerCaller)
    guard case .deliver(let request) = fixture.sent.first else {
      Issue.record("expected a deliver action")
      return
    }
    #expect(request.source == "manual")
  }

  @Test func anExplicitTargetThatDisagreesWithTheCallerPaneNeedsForce() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]
    fixture.answer = .failed(code: CLIErrorCode.stepNotExpecting, message: "no")

    let mismatch = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: session.run.id.uuidString, stepID: "launch", body: "x"),
      callerPane: Self.authorCaller)
    #expect(mismatch.error?.code == CLIErrorCode.roleMismatch)
    #expect(fixture.sent.isEmpty)

    let agreeing = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: session.run.id.uuidString, stepID: "brief", body: "x", token: "TOKEN-1"),
      callerPane: Self.authorCaller)
    #expect(agreeing.error?.code == CLIErrorCode.stepNotExpecting)
    guard case .deliver(let agreed) = fixture.sent.last else {
      Issue.record("expected a deliver action")
      return
    }
    #expect(agreed.source == "pane")
    #expect(agreed.ordinal == 1)

    _ = await fixture.coordinator.done(
      WorkflowInput(action: .done, runID: session.run.id.uuidString, stepID: "launch", body: "x", force: true),
      callerPane: Self.authorCaller)
    guard case .deliver(let forced) = fixture.sent.last else {
      Issue.record("expected a deliver action")
      return
    }
    #expect(forced.source == "manual --force")
    #expect(forced.selector == .manual(stepID: "launch"))
  }

  @Test func doneAwaitsTheReducerAndAProvisionalAnswerIsReportedAsProvisional() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]
    // No synchronous answer: the reducer resolves later, after persistence.
    let task = Task { @MainActor in
      await fixture.coordinator.done(
        WorkflowInput(action: .done, body: "## Scope\nonly", token: "TOKEN-1"), callerPane: Self.authorCaller)
    }
    await Task.yield()
    #expect(fixture.rendezvous.pendingRequestIDs == [fixture.requestID])
    var machine = session.machine(now: { Self.now }, makeToken: { "T" })
    let (result, _) = machine.deliver(ordinal: 1, selector: .token("TOKEN-1"), body: "## Scope\nonly", verdict: nil)
    _ = machine.apply(.outputPersisted(ordinal: 1))
    fixture.coordinator.resolve(fixture.requestID, .provisional(run: machine.run, receipt: try result.get()))
    let response = await task.value
    #expect(response.ok)
    guard case .done(let done) = try payload(response) else {
      Issue.record("expected a done payload")
      return
    }
    #expect(done.delivery.state == .provisional)
    #expect(done.delivery.warnings.map(\.code) == ["missing_sections"])
    #expect(done.run.status.state == "needs_attention")
    #expect(done.run.status.attention?.issues == ["missing_sections"])
  }

  // MARK: - status (decision W5)

  @Test func statusReadsTheCallerPaneRunALiveRunOrARecordedRun() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]

    let mine = fixture.coordinator.status(WorkflowInput(action: .status), callerPane: Self.authorCaller)
    guard case .status(let whoAmI) = try payload(mine) else {
      Issue.record("expected a status payload")
      return
    }
    #expect(whoAmI.source == .live)
    #expect(whoAmI.role == "author")
    #expect(whoAmI.step == "brief")
    #expect(whoAmI.activation?.expect.completion == ["PROWL_WORKFLOW_TOKEN=TOKEN-1 prowl workflow done -"])
    #expect(whoAmI.selfInitiated == nil)

    let stranger = fixture.coordinator.status(WorkflowInput(action: .status), callerPane: Self.strangerCaller)
    #expect(stranger.error?.code == CLIErrorCode.runNotFound)
    let outside = fixture.coordinator.status(WorkflowInput(action: .status), callerPane: nil)
    #expect(outside.error?.code == CLIErrorCode.sourceRequired)

    let byID = fixture.coordinator.status(
      WorkflowInput(action: .status, runID: session.run.id.uuidString), callerPane: Self.strangerCaller)
    guard case .status(let other) = try payload(byID) else {
      Issue.record("expected a status payload")
      return
    }
    #expect(other.role == nil)
    #expect(other.activation?.expect.completion == [], "tokens are spelled only to the role's own pane")

    // A run that is not live any more is read back from its record: no activation, no tokens.
    try session.store.ensureLayout(runID: session.run.id)
    try session.store.writeRecord(WorkflowRunRecord(run: session.run).interrupted(at: Self.now))
    fixture.sessions = []
    let recorded = fixture.coordinator.status(
      WorkflowInput(action: .status, runID: session.run.id.uuidString), callerPane: nil)
    guard case .status(let record) = try payload(recorded) else {
      Issue.record("expected a status payload")
      return
    }
    #expect(record.source == .record)
    #expect(record.status.state == "interrupted")
    #expect(record.activation == nil)
    #expect(record.bindings["author"]?.pane?.handle == "p1")

    let missing = fixture.coordinator.status(WorkflowInput(action: .status, runID: UUID().uuidString), callerPane: nil)
    #expect(missing.error?.code == CLIErrorCode.runNotFound)
    let malformed = fixture.coordinator.status(WorkflowInput(action: .status, runID: "x"), callerPane: nil)
    #expect(malformed.error?.code == CLIErrorCode.invalidArgument)
  }

  /// An invocation stuck in an injection attention has no activation `done` could address, so
  /// `status` must not advertise one (the caller would otherwise retry `done` forever).
  @Test func statusReportsNoActivationWhileTheStepIsInAnInjectionAttention() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    var session = try fixture.waitingSession()
    var machine = session.machine(now: { Self.now }, makeToken: { "T" })
    _ = machine.apply(.user(.cancel))
    _ = session
    // Rebuild a fresh session whose first step failed to inject.
    let definition = try #require(WorkflowDocumentParser.parse(WorkflowRunMachineTests.adversarialReview).definition)
    let started = try WorkflowRunMachine.start(
      WorkflowRunStartRequest(
        definition: definition, runID: UUID(),
        context: WorkflowRunContext(
          scope: .user, definitionPath: nil,
          worktree: WorkflowRunWorktree(
            id: "wt", name: "feature", branch: "feat/x", path: fixture.root.path(percentEncoded: false))),
        bindings: [
          "author": .current(WorkflowRunMachineTests.authorPane),
          "reviewer": .launch(WorkflowRunMachineTests.reviewerProfile, pane: nil),
        ]),
      now: { Self.now }, makeToken: { "T" })
    machine = started.machine
    _ = machine.apply(.roleUnavailable(ordinal: 1, .roleBlocked))
    session = WorkflowRunSession(
      run: machine.run,
      worktree: Worktree(
        id: "wt", name: "feature", detail: "", workingDirectory: fixture.root, repositoryRootURL: fixture.root),
      launchPlans: [:])
    fixture.sessions = [session]
    let response = fixture.coordinator.status(WorkflowInput(action: .status), callerPane: Self.authorCaller)
    guard case .status(let payload) = try payload(response) else {
      Issue.record("expected a status payload")
      return
    }
    #expect(payload.status.state == "needs_attention")
    #expect(payload.status.attention?.reason == "injection_failed:role_blocked")
    #expect(payload.activation == nil)
  }

  // MARK: - cancel

  @Test func cancelEntersTheReducerAndReportsTheEndedRun() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let session = try fixture.waitingSession()
    fixture.sessions = [session]

    let response = fixture.coordinator.cancel(
      WorkflowInput(action: .cancel, runID: session.run.id.uuidString), callerPane: Self.authorCaller)
    #expect(fixture.sent == [.userAction(runID: session.run.id, .cancel)])
    guard case .cancel(let cancelled) = try payload(response) else {
      Issue.record("expected a cancel payload")
      return
    }
    #expect(cancelled.status.state == "cancelled")
    #expect(cancelled.role == "author")

    let again = fixture.coordinator.cancel(
      WorkflowInput(action: .cancel, runID: session.run.id.uuidString), callerPane: nil)
    #expect(again.error?.code == CLIErrorCode.runNotFound)
    #expect(again.error?.message.contains("already ended") == true)
    let unknown = fixture.coordinator.cancel(WorkflowInput(action: .cancel, runID: UUID().uuidString), callerPane: nil)
    #expect(unknown.error?.code == CLIErrorCode.runNotFound)
  }
}
