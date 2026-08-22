import Foundation

/// Terminal-owned publication state for one multicast observer per surface.
/// The detector remains the producer of agent entries; this store is the
/// canonical replay/stream boundary shared by reducers and CLI observers.
@MainActor
final class AgentObservationStore {
  private struct SurfaceRecord {
    var agent: ActiveAgentEntry?
    var latestSignal: AgentSignal?
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

  init(bufferCapacity: Int) {
    self.bufferCapacity = max(1, bufferCapacity)
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

  func publishAgentChanged(_ entry: ActiveAgentEntry) {
    var record = records[entry.surfaceID] ?? SurfaceRecord()
    guard record.agent != entry else { return }
    record.agent = entry
    record.revision &+= 1
    records[entry.surfaceID] = record
    publish(.changed(entry), surfaceID: entry.surfaceID)
  }

  func publishAgentRemoved(surfaceID: UUID) {
    guard var record = records[surfaceID], record.agent != nil else { return }
    record.agent = nil
    record.revision &+= 1
    records[surfaceID] = record
    publish(.removed, surfaceID: surfaceID)
  }

  func publishSignal(_ signal: AgentSignal, surfaceID: UUID) {
    var record = records[surfaceID] ?? SurfaceRecord()
    record.latestSignal = signal
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
      case .dropped, .terminated:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
      @unknown default:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
      }
    }
  }

  func subscriberCount(surfaceID: UUID) -> Int {
    records[surfaceID]?.subscribers.count ?? 0
  }

  private func publish(_ event: ObservedAgentState, surfaceID: UUID) {
    guard var record = records[surfaceID] else { return }
    for (subscriberID, continuation) in record.subscribers {
      switch continuation.yield(event) {
      case .enqueued:
        continue
      case .dropped:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
        record.subscribers.removeValue(forKey: subscriberID)
      case .terminated:
        record.subscribers.removeValue(forKey: subscriberID)
      @unknown default:
        continuation.finish(throwing: AgentObservationError.bufferOverflow)
        record.subscribers.removeValue(forKey: subscriberID)
      }
    }
    records[surfaceID] = record
  }

  private func removeSubscriber(_ subscriberID: UUID, surfaceID: UUID) {
    guard var record = records[surfaceID] else { return }
    record.subscribers.removeValue(forKey: subscriberID)
    records[surfaceID] = record
  }
}
