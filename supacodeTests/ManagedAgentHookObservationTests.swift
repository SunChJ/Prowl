import Foundation
import Testing

@testable import supacode

@MainActor
struct ManagedAgentHookObservationTests {
  @Test func earlyHookWaitsForFirstTimelyGenerationThenVerifiesDeclaredCoverage() throws {
    let now = Date(timeIntervalSince1970: 100)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .claude, cwd: "/tmp/project")
    let epoch = store.registerManagedHook(registration, surfaceID: surfaceID)
    let input = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "SessionStart",
      event: .sessionStart,
      cwd: "/tmp/project"
    )

    #expect(
      store.recordManagedHook(
        input,
        callerAncestry: [AgentProcessGeneration(pid: 900, startedAt: now)],
        surfaceID: surfaceID
      ) == .pending
    )
    #expect(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true).channels.isEmpty)

    let update = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: AgentProcessGeneration(pid: 900, startedAt: now),
      sessionID: nil
    )
    #expect(update.activatedSignals.count == 1)
    #expect(update.activatedSignals[0].source == .hook(runtime: .claude, event: "SessionStart"))
    #expect(store.currentEvidenceEpoch(surfaceID: surfaceID) == epoch)
    let channel = try #require(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true).channels.first
    )
    #expect(channel.state == .verifiedLive)
    #expect(channel.events == [.needsInput, .sessionEnd, .sessionStart, .turnEnded])
  }

  @Test func wrongTokenRuntimeEventCWDAndGenerationFailClosed() {
    let now = Date(timeIntervalSince1970: 100)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: AgentProcessGeneration(pid: 900, startedAt: now),
      sessionID: nil
    )

    let rejected = [
      makeInput(runtime: .codex, token: "wrong", nativeEvent: "agent-turn-complete", cwd: "/tmp/project"),
      makeInput(runtime: .claude, token: registration.token, nativeEvent: "Stop", cwd: "/tmp/project"),
      makeInput(runtime: .codex, token: registration.token, nativeEvent: "future", cwd: "/tmp/project"),
      makeInput(runtime: .codex, token: registration.token, nativeEvent: "agent-turn-complete", cwd: "/tmp/other"),
    ]
    for input in rejected {
      #expect(
        store.recordManagedHook(
          input,
          callerAncestry: [AgentProcessGeneration(pid: 900, startedAt: now)],
          surfaceID: surfaceID
        ) == .rejected
      )
    }
    let valid = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project"
    )
    #expect(
      store.recordManagedHook(
        valid,
        callerAncestry: [AgentProcessGeneration(pid: 901, startedAt: now)],
        surfaceID: surfaceID
      ) == .rejected
    )
  }

  @Test func detectorNilCannotEraseVerifiedClaudeSessionOrAdmitDifferentStopSession() {
    let now = Date(timeIntervalSince1970: 100)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .claude, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: generation,
      sessionID: nil
    )
    let start = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "SessionStart",
      event: .sessionStart,
      cwd: "/tmp/project",
      sessionID: "session-1"
    )
    #expect(
      store.recordManagedHook(start, callerAncestry: [generation], surfaceID: surfaceID).isAccepted
    )

    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: generation,
      sessionID: nil
    )
    let wrongStop = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "Stop",
      event: .turnEnded,
      cwd: "/tmp/project",
      sessionID: "session-2"
    )

    #expect(
      store.recordManagedHook(wrongStop, callerAncestry: [generation], surfaceID: surfaceID)
        == .rejected
    )
  }

  @Test func detectorSessionReplacementRequiresClaudeSessionStartBeforeReverification() throws {
    let now = Date(timeIntervalSince1970: 100)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .claude, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)
    let first = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "SessionStart",
      event: .sessionStart,
      cwd: "/tmp/project",
      sessionID: "session-1"
    )
    #expect(store.recordManagedHook(first, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)

    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: generation,
      sessionID: "session-2"
    )
    let stop = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "Stop",
      event: .turnEnded,
      cwd: "/tmp/project",
      sessionID: "session-2"
    )
    #expect(store.recordManagedHook(stop, callerAncestry: [generation], surfaceID: surfaceID) == .rejected)
    #expect(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true)
        .channels.isEmpty
    )

    let second = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "SessionStart",
      event: .sessionStart,
      cwd: "/tmp/project",
      sessionID: "session-2"
    )
    #expect(store.recordManagedHook(second, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
    let channel = try #require(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true)
        .channels.first
    )
    #expect(channel.sessionID == "session-2")
  }

  @Test func staleDetectorSessionDoesNotRollBackAHookAnnouncedNewSession() throws {
    // Claude/Droid/Qoder announce their own sessions, so the detector's screen-derived
    // session must never rotate the channel: a lagging read of the previous session would
    // otherwise revoke the just-verified new one and roll `record.sessionID` backwards.
    let now = Date(timeIntervalSince1970: 100)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let registration = makeRegistration(runtime: .claude, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)

    func sessionStart(_ session: String) -> AgentNativeHookInput {
      makeInput(
        runtime: .claude, token: registration.token, nativeEvent: "SessionStart",
        event: .sessionStart, cwd: "/tmp/project", sessionID: session)
    }
    #expect(store.recordManagedHook(sessionStart("S1"), callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
    #expect(store.recordManagedHook(sessionStart("S2"), callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
    let epochAfterS2 = try #require(store.currentEvidenceEpoch(surfaceID: surfaceID))

    // The detector resolver lags and still reports the previous session S1.
    let update = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: "S1")
    #expect(update.revokedForwardingRecords.isEmpty)
    #expect(store.currentEvidenceEpoch(surfaceID: surfaceID) == epochAfterS2)
    let channel = try #require(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true).channels.first)
    #expect(channel.state == .verifiedLive)
    #expect(channel.sessionID == "S2")

    // A later Stop for the current session S2 is still accepted without a rotation.
    #expect(
      store.recordManagedHook(
        makeInput(
          runtime: .claude, token: registration.token, nativeEvent: "Stop", event: .turnEnded,
          cwd: "/tmp/project", sessionID: "S2"),
        callerAncestry: [generation], surfaceID: surfaceID
      ).isAccepted)
    #expect(store.currentEvidenceEpoch(surfaceID: surfaceID) == epochAfterS2)
  }

  @Test func processReplacementRevokesTrustAndReturnsForwardRecordForRetirement() {
    let now = Date(timeIntervalSince1970: 100)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let forward = CodexForwardingRecord(locator: URL(filePath: "/tmp/private/record.json"))
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project", forwardingRecord: forward)
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: AgentProcessGeneration(pid: 900, startedAt: now),
      sessionID: nil
    )

    let replacement = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: AgentProcessGeneration(pid: 901, startedAt: now.addingTimeInterval(1)),
      sessionID: nil
    )
    #expect(replacement.revokedForwardingRecords == [forward])
    let input = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project"
    )
    #expect(
      store.recordManagedHook(
        input,
        callerAncestry: [AgentProcessGeneration(pid: 901, startedAt: now.addingTimeInterval(1))],
        surfaceID: surfaceID
      ) == .rejected
    )
  }

  @Test func transientGenerationLookupFailureKeepsManagedTrustAndForwarding() {
    let now = Date(timeIntervalSince1970: 100)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let forward = CodexForwardingRecord(locator: URL(filePath: "/tmp/private/record.json"))
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project", forwardingRecord: forward)
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)

    let missing = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: nil,
      sessionID: nil
    )

    #expect(missing.revokedForwardingRecords.isEmpty)
    #expect(store.hasManagedHook(surfaceID: surfaceID))
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)
    let input = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project"
    )
    #expect(store.recordManagedHook(input, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
  }

  @Test func lateFirstManagedGenerationStillAttachesToThePreparedLaunch() {
    var now = Date(timeIntervalSince1970: 100)
    let store = AgentObservationStore(
      bufferCapacity: 8,
      now: { now },
      dispatchGenerationWindow: 10
    )
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    now.addTimeInterval(11)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)

    let update = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: generation,
      sessionID: nil
    )
    let input = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project"
    )

    #expect(update.revokedForwardingRecords.isEmpty)
    #expect(store.hasManagedHook(surfaceID: surfaceID))
    #expect(store.recordManagedHook(input, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
  }

  @Test func codexThreadRotationRebindsTheManagedHook() throws {
    let now = Date(timeIntervalSince1970: 100)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)
    let first = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project",
      sessionID: "thread-1"
    )
    #expect(store.recordManagedHook(first, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)

    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: generation,
      sessionID: "thread-2"
    )
    let second = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project",
      sessionID: "thread-2"
    )

    #expect(store.recordManagedHook(second, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
    let channel = try #require(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true)
        .channels.first
    )
    #expect(channel.sessionID == "thread-2")
  }

  @Test func detectorConfirmedThreadRotationRejectsLatePreviousThreadHook() {
    let now = Date(timeIntervalSince1970: 100)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)
    let first = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project",
      sessionID: "thread-1"
    )
    #expect(store.recordManagedHook(first, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)

    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: generation,
      sessionID: "thread-2"
    )

    #expect(!store.recordManagedHook(first, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
    let second = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project",
      sessionID: "thread-2"
    )
    #expect(store.recordManagedHook(second, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
  }

  @Test func hookDrivenThreadRotationRejectsLatePreviousThreadHook() {
    let now = Date(timeIntervalSince1970: 100)
    let generation = AgentProcessGeneration(pid: 900, startedAt: now)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .codex, cwd: "/tmp/project")
    _ = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(surfaceID: surfaceID, processGeneration: generation, sessionID: nil)
    let first = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project",
      sessionID: "thread-1"
    )
    let second = makeInput(
      runtime: .codex,
      token: registration.token,
      nativeEvent: "agent-turn-complete",
      cwd: "/tmp/project",
      sessionID: "thread-2"
    )
    #expect(store.recordManagedHook(first, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
    #expect(store.recordManagedHook(second, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)

    #expect(!store.recordManagedHook(first, callerAncestry: [generation], surfaceID: surfaceID).isAccepted)
  }

  @Test func processReplacementClearsThePreviousSessionIdentity() {
    let now = Date(timeIntervalSince1970: 100)
    let first = AgentProcessGeneration(pid: 900, startedAt: now)
    let second = AgentProcessGeneration(pid: 901, startedAt: now.addingTimeInterval(1))
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: first,
      sessionID: "session-1"
    )

    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: second,
      sessionID: nil
    )

    #expect(
      store.bindingForSignal(
        surfaceID: surfaceID,
        generationMatches: true,
        signalSessionID: "session-2"
      ) == .current
    )
  }

  @Test func validClaudeSessionStartRotatesFreshnessButRetainsLaunchChannel() throws {
    let now = Date(timeIntervalSince1970: 100)
    let store = AgentObservationStore(bufferCapacity: 8, now: { now })
    let surfaceID = UUID()
    let registration = makeRegistration(runtime: .claude, cwd: "/tmp/project")
    let firstEpoch = store.registerManagedHook(registration, surfaceID: surfaceID)
    _ = store.updateEvidenceEpoch(
      surfaceID: surfaceID,
      processGeneration: AgentProcessGeneration(pid: 900, startedAt: now),
      sessionID: nil
    )
    let first = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "SessionStart",
      event: .sessionStart,
      cwd: "/tmp/project",
      sessionID: "session-1"
    )
    #expect(
      store.recordManagedHook(
        first,
        callerAncestry: [AgentProcessGeneration(pid: 900, startedAt: now)],
        surfaceID: surfaceID
      ).isAccepted
    )

    let second = makeInput(
      runtime: .claude,
      token: registration.token,
      nativeEvent: "SessionStart",
      event: .sessionStart,
      cwd: "/tmp/project",
      sessionID: "session-2"
    )
    #expect(
      store.recordManagedHook(
        second,
        callerAncestry: [AgentProcessGeneration(pid: 900, startedAt: now)],
        surfaceID: surfaceID
      ).isAccepted
    )
    #expect(store.currentEvidenceEpoch(surfaceID: surfaceID) != firstEpoch)
    let channel = try #require(
      store.signalsPayload(surfaceID: surfaceID, formatter: formatter, includeDiagnosticLast: true).channels.first
    )
    #expect(channel.state == .verifiedLive)
    #expect(channel.sessionID == "session-2")
  }

  private var formatter: ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private func makeRegistration(
    runtime: AgentNativeHookRuntime,
    cwd: String,
    forwardingRecord: CodexForwardingRecord? = nil
  ) -> AgentHookLaunchRegistration {
    let nativeEvents: [String: AgentSignalEvent] =
      runtime == .claude
      ? [
        "SessionStart": .sessionStart, "Stop": .turnEnded, "SessionEnd": .sessionEnd, "PermissionRequest": .needsInput,
      ]
      : ["agent-turn-complete": .turnEnded]
    return AgentHookLaunchRegistration(
      token: "token-123",
      runtime: runtime,
      launchCWD: URL(filePath: cwd, directoryHint: .isDirectory),
      nativeEvents: nativeEvents,
      coveredEvents: Array(Set(nativeEvents.values)).sorted { $0.rawValue < $1.rawValue },
      forwardingRecord: forwardingRecord
    )
  }

  private func makeInput(
    runtime: AgentNativeHookRuntime,
    token: String,
    nativeEvent: String,
    event: AgentSignalEvent = .turnEnded,
    cwd: String,
    sessionID: String = "session-1"
  ) -> AgentNativeHookInput {
    AgentNativeHookInput(
      runtime: runtime,
      token: token,
      signal: AgentNativeHookSignal(
        event: event,
        nativeEvent: nativeEvent,
        cwd: cwd,
        sessionID: sessionID
      )
    )
  }
}

extension ManagedHookRecordResult {
  fileprivate var isAccepted: Bool {
    if case .accepted = self { return true }
    return false
  }
}
