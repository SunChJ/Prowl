import Foundation

private struct AgentSignalChannelRecord {
  var confidence: AgentSignal.Confidence
  var events: [AgentSignalEvent]
  var lastSeenAt: Date
  var sessionID: String?
}

struct AgentCurrentSignalEvidence: Sendable {
  let activeTerminal: AgentSignal?
  let latest: AgentSignal?
}

/// Terminal-owned publication state for one multicast observer per surface.
/// The detector remains the producer of agent entries; this store is the
/// canonical replay/stream boundary shared by reducers and CLI observers.
@MainActor
final class AgentObservationStore {
  private struct SurfaceRecord {
    var agent: ActiveAgentEntry?
    var latestSignal: AgentSignal?
    var latestSignalBinding: AgentSignalBinding?
    var latestCurrentSignal: AgentSignal?
    var activeTerminalSignal: AgentSignal?
    var processGeneration: AgentProcessGeneration?
    var sessionID: String?
    var sessionlessSignalsAllowed = true
    var evidenceEpoch = UUID()
    var awaitingFirstProcessGeneration = false
    var firstProcessGenerationStartedBefore: Date?
    var channels: [String: AgentSignalChannelRecord] = [:]
    var revision: UInt64 = 0
    var subscribers: [UUID: AgentObservationStream.Continuation] = [:]

    var snapshot: AgentObservationSnapshot {
      AgentObservationSnapshot(
        agent: agent,
        latestSignal: latestSignal,
        revision: revision
      )
    }
  }

  private var records: [UUID: SurfaceRecord] = [:]
  private let bufferCapacity: Int
  private let now: @MainActor () -> Date
  /// The launched process starts immediately; this spans more than three idle detection polls
  /// while refusing a manually started replacement long after a missed short-lived runtime.
  private let dispatchGenerationWindow: TimeInterval

  init(
    bufferCapacity: Int,
    now: @escaping @MainActor () -> Date = Date.init,
    dispatchGenerationWindow: TimeInterval = 10
  ) {
    self.bufferCapacity = max(1, bufferCapacity)
    self.now = now
    self.dispatchGenerationWindow = max(0, dispatchGenerationWindow)
  }

  func observe(surfaceID: UUID, isLive: Bool) -> AgentObservationStream {
    guard isLive else {
      return AgentObservationStream(bufferingPolicy: .unbounded) { continuation in
        continuation.yield(
          .snapshot(
            AgentObservationSnapshot(agent: nil, latestSignal: nil, revision: 0)
          ))
        continuation.yield(.surfaceClosed)
        continuation.finish()
      }
    }

    let subscriberID = UUID()
    var continuation: AgentObservationStream.Continuation?
    let stream = AgentObservationStream(
      bufferingPolicy: .bufferingOldest(bufferCapacity)
    ) { continuation = $0 }
    guard let continuation else { return stream }

    continuation.onTermination = { @Sendable [weak self] _ in
      Task { @MainActor [weak self] in
        self?.removeSubscriber(subscriberID, surfaceID: surfaceID)
      }
    }

    var record = records[surfaceID] ?? SurfaceRecord()
    record.subscribers[subscriberID] = continuation
    let snapshot = record.snapshot
    records[surfaceID] = record
    continuation.yield(.snapshot(snapshot))
    return stream
  }

  /// Callers must establish that the surface is live before publishing. The
  /// manager owns that invariant: detector callbacks come only from live state,
  /// and cooperative signals pass its `containsSurface` guard.
  @discardableResult
  func publishAgentChanged(_ entry: ActiveAgentEntry) -> Bool {
    var record = records[entry.surfaceID] ?? SurfaceRecord()
    guard record.agent != entry else { return false }
    let beganWorking =
      record.agent.map { $0.displayState != .working && entry.displayState == .working }
      ?? false
    record.agent = entry
    if beganWorking {
      record.activeTerminalSignal = nil
    }
    record.revision &+= 1
    records[entry.surfaceID] = record
    publish(.changed(entry), surfaceID: entry.surfaceID)
    return beganWorking
  }

  func publishAgentRemoved(surfaceID: UUID) {
    guard var record = records[surfaceID], record.agent != nil else { return }
    record.agent = nil
    record.revision &+= 1
    records[surfaceID] = record
    publish(.removed, surfaceID: surfaceID)
  }

  /// The manager validates surface liveness before this publication seam.
  func publishSignal(_ signal: AgentSignal, surfaceID: UUID) {
    publishSignal(signal, binding: .unbound, surfaceID: surfaceID)
  }

  func publishSignal(
    _ signal: AgentSignal,
    binding: AgentSignalBinding,
    surfaceID: UUID
  ) {
    var record = records[surfaceID] ?? SurfaceRecord()
    record.latestSignal = signal
    record.latestSignalBinding = binding
    if binding == .current {
      record.latestCurrentSignal = signal
      switch signal.event {
      case .turnEnded, .needsInput, .sessionEnd:
        record.activeTerminalSignal = signal
      case .sessionStart, .progress:
        record.activeTerminalSignal = nil
      }
      let source = signal.source.payloadName
      var channel =
        record.channels[source]
        ?? AgentSignalChannelRecord(
          confidence: signal.confidence,
          events: [],
          lastSeenAt: signal.timestamp,
          sessionID: signal.sessionID
        )
      if !channel.events.contains(signal.event) { channel.events.append(signal.event) }
      channel.confidence = signal.confidence
      channel.lastSeenAt = signal.timestamp
      channel.sessionID = signal.sessionID
      record.channels[source] = channel
    }
    record.revision &+= 1
    records[surfaceID] = record
    publish(.signal(signal), surfaceID: surfaceID)
  }

  func publishSurfaceClosed(surfaceID: UUID) {
    guard records[surfaceID] != nil else { return }
    publishAgentRemoved(surfaceID: surfaceID)
    guard let record = records.removeValue(forKey: surfaceID) else { return }
    for continuation in record.subscribers.values {
      switch continuation.yield(.surfaceClosed) {
      case .enqueued:
        continuation.finish()
      case .dropped:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
      case .terminated:
        continue
      @unknown default:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
      }
    }
  }

  /// Internal diagnostic seam used by cancellation tests and available to S2
  /// when it exposes per-pane signal capability health.
  func subscriberCount(surfaceID: UUID) -> Int {
    records[surfaceID]?.subscribers.count ?? 0
  }

  func snapshot(surfaceID: UUID) -> AgentObservationSnapshot? {
    records[surfaceID]?.snapshot
  }

  func currentSignalEvidence(surfaceID: UUID) -> AgentCurrentSignalEvidence {
    guard let record = records[surfaceID] else {
      return AgentCurrentSignalEvidence(activeTerminal: nil, latest: nil)
    }
    return AgentCurrentSignalEvidence(
      activeTerminal: record.activeTerminalSignal,
      latest: record.latestCurrentSignal
    )
  }

  func beginDispatchEpoch(surfaceID: UUID) -> UUID {
    var record = records[surfaceID] ?? SurfaceRecord()
    record.evidenceEpoch = UUID()
    record.processGeneration = nil
    record.sessionID = nil
    record.sessionlessSignalsAllowed = true
    record.awaitingFirstProcessGeneration = true
    record.firstProcessGenerationStartedBefore = now().addingTimeInterval(
      dispatchGenerationWindow
    )
    record.channels.removeAll()
    record.latestCurrentSignal = nil
    record.activeTerminalSignal = nil
    if record.latestSignal != nil { record.latestSignalBinding = .stale }
    records[surfaceID] = record
    return record.evidenceEpoch
  }

  func currentEvidenceEpoch(surfaceID: UUID) -> UUID? {
    records[surfaceID]?.evidenceEpoch
  }

  func updateEvidenceEpoch(
    surfaceID: UUID,
    processGeneration: AgentProcessGeneration?,
    sessionID: String?
  ) {
    var record = records[surfaceID] ?? SurfaceRecord()
    let firstGenerationIsTimely =
      processGeneration.map {
        $0.startedAt <= (record.firstProcessGenerationStartedBefore ?? .distantPast)
      } ?? false
    let attachesFirstLaunchGeneration =
      record.awaitingFirstProcessGeneration
      && record.processGeneration == nil
      && firstGenerationIsTimely
    let rejectsLateFirstGeneration =
      record.awaitingFirstProcessGeneration
      && record.processGeneration == nil
      && processGeneration != nil
      && !firstGenerationIsTimely
    let processChanged =
      rejectsLateFirstGeneration
      || (!attachesFirstLaunchGeneration && record.processGeneration != processGeneration)
    let sessionChanged =
      !processChanged
      && record.sessionID != nil
      && sessionID != nil
      && record.sessionID != sessionID
    if processChanged || sessionChanged {
      record.evidenceEpoch = UUID()
      record.channels.removeAll()
      record.latestCurrentSignal = nil
      record.activeTerminalSignal = nil
      if record.latestSignal != nil { record.latestSignalBinding = .stale }
      record.sessionlessSignalsAllowed = processChanged
    }
    if attachesFirstLaunchGeneration || rejectsLateFirstGeneration {
      record.awaitingFirstProcessGeneration = false
      record.firstProcessGenerationStartedBefore = nil
    }
    record.processGeneration = processGeneration
    record.sessionID = sessionID
    records[surfaceID] = record
  }

  func bindingForSignal(
    surfaceID: UUID,
    generationMatches: Bool,
    signalSessionID: String?
  ) -> AgentSignalBinding {
    guard generationMatches, var record = records[surfaceID] else { return .unbound }
    if let signalSessionID {
      if let current = record.sessionID, current != signalSessionID { return .unbound }
      if record.sessionID == nil {
        record.sessionID = signalSessionID
        records[surfaceID] = record
      }
      return .current
    }
    return record.sessionlessSignalsAllowed ? .current : .unbound
  }

  func signalsPayload(
    surfaceID: UUID,
    formatter: ISO8601DateFormatter,
    includeDiagnosticLast: Bool
  ) -> AgentSignalsPayload {
    guard let record = records[surfaceID] else { return .empty }
    let channels = record.channels
      .map { source, channel in
        AgentSignalChannelPayload(
          source: source,
          state: .observed,
          confidence: channel.confidence.rawValue,
          events: channel.events.sorted { $0.rawValue < $1.rawValue },
          lastSeenAt: formatter.string(from: channel.lastSeenAt),
          sessionID: channel.sessionID
        )
      }
      .sorted { $0.source < $1.source }
    let mayExposeLast = includeDiagnosticLast || record.latestSignalBinding == .current
    let last =
      mayExposeLast
      ? record.latestSignal.map {
        $0.payload(timestamp: formatter.string(from: $0.timestamp))
      } : nil
    return AgentSignalsPayload(
      channels: channels,
      last: last,
      lastBinding: last == nil ? nil : (record.latestSignalBinding ?? .unbound)
    )
  }

  private func publish(_ event: ObservedAgentState, surfaceID: UUID) {
    guard let subscribers = records[surfaceID]?.subscribers else { return }
    for (subscriberID, continuation) in subscribers {
      switch continuation.yield(event) {
      case .enqueued:
        continue
      case .dropped:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
        records[surfaceID]?.subscribers.removeValue(forKey: subscriberID)
      case .terminated:
        records[surfaceID]?.subscribers.removeValue(forKey: subscriberID)
      @unknown default:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
        records[surfaceID]?.subscribers.removeValue(forKey: subscriberID)
      }
    }
  }

  private func removeSubscriber(_ subscriberID: UUID, surfaceID: UUID) {
    guard var record = records[surfaceID] else { return }
    record.subscribers.removeValue(forKey: subscriberID)
    records[surfaceID] = record
  }
}
