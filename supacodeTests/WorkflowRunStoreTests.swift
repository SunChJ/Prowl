import Foundation
import Testing

@testable import supacode

struct WorkflowRunStoreTests {
  nonisolated private static let now = Date(timeIntervalSince1970: 1_760_000_000)

  private func makeRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "workflow-run-store-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func makeRun(root: URL, status: WorkflowRunStatus = .running) throws -> WorkflowRun {
    let definition = try #require(WorkflowDocumentParser.parse(WorkflowRunMachineTests.handoff).definition)
    let started = try WorkflowRunMachine.start(
      WorkflowRunStartRequest(
        definition: definition,
        runID: UUID(),
        context: WorkflowRunContext(
          scope: .repo(repositoryID: "repo-1"), definitionPath: "/x/review.yaml",
          worktree: WorkflowRunWorktree(
            id: "wt", name: "feature", branch: "feat/x", path: root.path(percentEncoded: false))),
        bindings: [
          "source": .current(WorkflowRunMachineTests.authorPane),
          "receiver": .launch(WorkflowRunMachineTests.reviewerProfile, pane: nil),
        ]),
      now: { Self.now },
      makeToken: { "SECRET-TOKEN" })
    var machine = started.machine
    _ = machine.apply(.roleIdle(ordinal: 1))
    _ = machine.apply(.injectionSucceeded(ordinal: 1, dispatchID: "dispatch-1"))
    if case .needsAttention = status {
      _ = machine.apply(.watchdog(ordinal: 1, .attention(.idleWithoutDelivery)))
    }
    if status == .cancelled {
      _ = machine.apply(.user(.cancel))
    }
    return machine.run
  }

  @Test func layoutCreatesTheSelfIgnoringRunsDirectoryAndSubdirectories() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    let runs = root.appending(path: ".prowl/workflow-runs", directoryHint: .isDirectory)
    #expect(try String(contentsOf: runs.appending(path: ".gitignore"), encoding: .utf8) == "*\n")
    for name in ["instructions", "outputs", "skills"] {
      var isDirectory: ObjCBool = false
      let path = runs.appending(path: runID.uuidString).appending(path: name).path(percentEncoded: false)
      #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }
  }

  @Test func recordRoundTripsWithoutTokensOrEnvironment() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let run = try makeRun(
      root: root,
      status: .needsAttention(
        WorkflowAttention(
          reason: .idleWithoutDelivery, stepID: "brief", role: "source", ordinal: 1, actions: [], message: "")))
    try store.ensureLayout(runID: run.id)
    let record = WorkflowRunRecord(run: run)
    try store.writeRecord(record)

    let url = store.directory(for: run.id).appending(path: "run.json")
    let json = try String(contentsOf: url, encoding: .utf8)
    #expect(!json.contains("SECRET-TOKEN"))
    #expect(json.contains("\"dispatch_id\" : \"dispatch-1\""))
    #expect(json.contains("\"version\" : 1"))
    #expect(json.contains("\"scope\" : \"repo:repo-1\""))
    #expect(json.contains("\"state\" : \"needs_attention\""))
    #expect(json.contains("\"reason\" : \"idle_without_delivery\""))
    #expect(json.contains("\"agent\" : \"pi\""))
    #expect(!json.contains("PROWL_"))

    let decoded = try store.readRecord(runID: run.id)
    #expect(decoded == record)
    #expect(decoded.inputs == [])
    #expect(decoded.bindings["receiver"]?.profile == WorkflowRunMachineTests.reviewerProfile)
    #expect(decoded.bindings["source"]?.pane == WorkflowRunMachineTests.authorPane)
    #expect(decoded.invocations.first?.activation?.output == "brief")
    #expect(decoded.run.status.attention?.actions == [.nudge, .keepWaiting, .skip, .cancel])
  }

  @Test func recordKeepsInputNamesButNeverInputValues() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let definition = try #require(WorkflowDocumentParser.parse(WorkflowRunMachineTests.adversarialReview).definition)
    let started = try WorkflowRunMachine.start(
      WorkflowRunStartRequest(
        definition: definition,
        runID: UUID(),
        context: WorkflowRunContext(
          scope: .user, definitionPath: nil,
          worktree: WorkflowRunWorktree(id: "wt", name: "w", branch: "b", path: root.path(percentEncoded: false))),
        bindings: [
          "author": .current(WorkflowRunMachineTests.authorPane),
          "reviewer": .launch(WorkflowRunMachineTests.reviewerProfile, pane: nil),
        ],
        inputs: ["focus": "hunter2-secret"]),
      now: { Self.now })
    let store = WorkflowRunStore(rootURL: root)
    try store.ensureLayout(runID: started.machine.run.id)
    try store.writeRecord(WorkflowRunRecord(run: started.machine.run))
    let json = try String(
      contentsOf: store.directory(for: started.machine.run.id).appending(path: "run.json"), encoding: .utf8)
    #expect(!json.contains("hunter2-secret"))
    #expect(try store.readRecord(runID: started.machine.run.id).inputs == ["focus", "max_rounds", "mode"])
  }

  @Test func symlinkedLogAndRecordLeavesAreRefused() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    let victim = root.appending(path: "victim.txt")
    try "original\n".write(to: victim, atomically: true, encoding: .utf8)
    let log = store.directory(for: runID).appending(path: "log.md")
    try FileManager.default.createSymbolicLink(at: log, withDestinationURL: victim)
    #expect(throws: WorkflowRunStoreError.self) { try store.appendLog(runID: runID, line: "hi", now: Self.now) }
    #expect(try String(contentsOf: victim, encoding: .utf8) == "original\n")
    let record = store.directory(for: runID).appending(path: "run.json")
    try FileManager.default.createSymbolicLink(at: record, withDestinationURL: victim)
    #expect(throws: WorkflowRunStoreError.self) { try store.readRecord(runID: runID) }
    let run = try makeRun(root: root)
    try store.ensureLayout(runID: run.id)
    try FileManager.default.createSymbolicLink(
      at: store.directory(for: run.id).appending(path: "run.json"), withDestinationURL: victim)
    #expect(throws: WorkflowRunStoreError.self) { try store.writeRecord(WorkflowRunRecord(run: run)) }
    #expect(try String(contentsOf: victim, encoding: .utf8) == "original\n")
  }

  @Test func recordDecodingToleratesUnknownKeys() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let run = try makeRun(root: root)
    try store.ensureLayout(runID: run.id)
    try store.writeRecord(WorkflowRunRecord(run: run))
    let url = store.directory(for: run.id).appending(path: "run.json")
    var json = try String(contentsOf: url, encoding: .utf8)
    json = json.replacing("\"version\" : 1", with: "\"version\" : 1,\n  \"future_key\" : { \"nested\" : true }")
    try json.write(to: url, atomically: true, encoding: .utf8)
    #expect(try store.readRecord(runID: run.id).run.id == run.id)
  }

  @Test func outputsAreVersionedAndTheLatestViewIsReplacedAtomically() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    let first = try store.writeOutput(runID: runID, name: "findings", ordinal: 2, body: "round 1\n")
    let second = try store.writeOutput(runID: runID, name: "findings", ordinal: 4, body: "round 2\n")
    #expect(first.versioned.lastPathComponent == "findings.2.md")
    #expect(second.versioned.lastPathComponent == "findings.4.md")
    #expect(first.latest == second.latest)
    #expect(try String(contentsOf: first.versioned, encoding: .utf8) == "round 1\n")
    #expect(try String(contentsOf: second.latest, encoding: .utf8) == "round 2\n")
    let leftovers = try FileManager.default.contentsOfDirectory(
      atPath: second.latest.deletingLastPathComponent().path(percentEncoded: false))
    #expect(leftovers.sorted() == ["findings.2.md", "findings.4.md", "findings.md"])
  }

  @Test func instructionsAndLogAreWrittenUnderTheRun() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    let instruction = try store.writeInstruction(runID: runID, stepID: "brief", ordinal: 1, text: "Do it.\n")
    #expect(instruction.lastPathComponent == "brief.1.md")
    #expect(try String(contentsOf: instruction, encoding: .utf8) == "Do it.\n")
    try store.appendLog(runID: runID, line: "started", now: Self.now)
    try store.appendLog(runID: runID, line: "two\nlines", now: Self.now)
    let log = try String(contentsOf: store.directory(for: runID).appending(path: "log.md"), encoding: .utf8)
    #expect(
      log
        == "# Workflow run \(runID.uuidString)\n\n- 2025-10-09T08:53:20Z  started\n- 2025-10-09T08:53:20Z  two lines\n")
  }

  @Test func unsafeSlugsAreRejectedBeforeTouchingTheDisk() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    #expect(throws: WorkflowRunStoreError.unsafePath("../escape")) {
      try store.writeInstruction(runID: runID, stepID: "../escape", ordinal: 1, text: "x")
    }
    #expect(throws: WorkflowRunStoreError.unsafePath("Bad Name")) {
      try store.writeOutput(runID: runID, name: "Bad Name", ordinal: 1, body: "x")
    }
    #expect(throws: WorkflowRunStoreError.unsafePath("brief")) {
      try store.writeInstruction(runID: runID, stepID: "brief", ordinal: 0, text: "x")
    }
  }

  @Test func symlinkedRunDirectoryLeafIsRejected() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try FileManager.default.createDirectory(at: store.runsDirectory, withIntermediateDirectories: true)
    let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: store.directory(for: runID), withDestinationURL: elsewhere)
    #expect(
      throws: WorkflowRunStoreError.symbolicLink(
        store.directory(for: runID).path(percentEncoded: false).trimmingSuffix("/"))
    ) {
      try store.ensureLayout(runID: runID)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path(percentEncoded: false)).isEmpty)
  }

  @Test func symlinkedOutputsDirectoryIsRejected() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    let outputs = store.directory(for: runID).appending(path: "outputs", directoryHint: .isDirectory)
    try FileManager.default.removeItem(at: outputs)
    let elsewhere = root.appending(path: "elsewhere", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: outputs, withDestinationURL: elsewhere)
    #expect(throws: WorkflowRunStoreError.self) {
      try store.writeOutput(runID: runID, name: "findings", ordinal: 1, body: "x")
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path(percentEncoded: false)).isEmpty)
  }

  @Test func skillIsMaterializedFromTheBundleDirectory() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let bundle = root.appending(path: "bundle/skills/prowl.adversarial-reviewer", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try "---\nname: reviewer\ndescription: Review.\n---\n# Review\n".write(
      to: bundle.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    try "checklist".write(to: bundle.appending(path: "checklist.md"), atomically: true, encoding: .utf8)
    let skill = BundledSkill(
      id: "prowl.adversarial-reviewer", name: "reviewer", description: "Review.", audience: .workflow,
      directoryURL: bundle)
    let store = WorkflowRunStore(rootURL: root)
    let runID = UUID()
    try store.ensureLayout(runID: runID)
    let destination = try store.materializeSkill(runID: runID, skill: skill)
    #expect(
      destination
        == store.directory(for: runID).appending(path: "skills/prowl.adversarial-reviewer", directoryHint: .isDirectory)
    )
    #expect(try String(contentsOf: destination.appending(path: "SKILL.md"), encoding: .utf8).hasSuffix("# Review\n"))
    #expect(
      FileManager.default.fileExists(atPath: destination.appending(path: "checklist.md").path(percentEncoded: false)))
    _ = try store.materializeSkill(runID: runID, skill: skill)
    let missing = BundledSkill(
      id: "prowl.nope", name: "n", description: "d", audience: .workflow, directoryURL: root.appending(path: "nope"))
    #expect(throws: WorkflowRunStoreError.skillMissing("prowl.nope")) {
      try store.materializeSkill(runID: runID, skill: missing)
    }
  }

  @Test func interruptedScanFlipsOnlyNonTerminalRunsAndReportsUnreadableOnes() throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = WorkflowRunStore(rootURL: root)
    #expect(try store.markInterruptedRuns(now: Self.now) == WorkflowInterruptedRuns(interrupted: [], unreadable: []))

    let running = try makeRun(root: root)
    let attention = try makeRun(
      root: root,
      status: .needsAttention(
        WorkflowAttention(reason: .blocked, stepID: "brief", role: nil, ordinal: nil, actions: [], message: "")))
    let cancelled = try makeRun(root: root, status: .cancelled)
    for run in [running, attention, cancelled] {
      try store.ensureLayout(runID: run.id)
      try store.writeRecord(WorkflowRunRecord(run: run))
    }
    let brokenID = UUID()
    try store.ensureLayout(runID: brokenID)
    try "{ not json".write(
      to: store.directory(for: brokenID).appending(path: "run.json"), atomically: true, encoding: .utf8)
    let later = Self.now.addingTimeInterval(60)
    let result = try store.markInterruptedRuns(now: later)
    #expect(Set(result.interrupted) == [running.id, attention.id])
    #expect(
      result.unreadable == [store.directory(for: brokenID).appending(path: "run.json").path(percentEncoded: false)])
    let flipped = try store.readRecord(runID: running.id)
    #expect(flipped.run.status.state == "interrupted")
    #expect(flipped.run.finishedAt == later)
    #expect(flipped.invocations.count == 1)
    #expect(try store.readRecord(runID: cancelled.id).run.status.state == "cancelled")
    let log = try String(contentsOf: store.directory(for: running.id).appending(path: "log.md"), encoding: .utf8)
    #expect(log.contains("marked interrupted"))
    #expect(try store.markInterruptedRuns(now: later).interrupted.isEmpty)
  }
}

extension String {
  fileprivate func trimmingSuffix(_ suffix: String) -> String {
    hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
  }
}
