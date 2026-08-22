import Foundation

struct AgentSignal: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case turnEnded
    case needsInput
    case sessionStart
    case sessionEnd
    case progress(Int?)
  }

  enum Source: Equatable, Sendable {
    case cooperativeCLI
    case hook(runtime: AgentProfileRuntime, event: String)
    case transcript
    case process
    case osc
    case screen
  }

  enum Confidence: String, Equatable, Sendable {
    case exact
    case high
    case heuristic
  }

  let kind: Kind
  let source: Source
  let confidence: Confidence
  let timestamp: Date
  let sessionID: String?
  let detail: String?
  /// Caller-authored provenance hint. It never upgrades `source` or `confidence`.
  let claimedOrigin: String?
}

struct AgentObservationSnapshot: Equatable, Sendable {
  let agent: ActiveAgentEntry?
  let latestSignal: AgentSignal?
  /// Monotonic within one live surface. Consumers use it to recognize a newer
  /// resubscription snapshot after an overflow; it is not a persisted cursor.
  let revision: UInt64
}

enum ObservedAgentState: Equatable, Sendable {
  case snapshot(AgentObservationSnapshot)
  case changed(ActiveAgentEntry)
  case removed
  case signal(AgentSignal)
  case surfaceClosed
}

enum AgentObservationError: Error, Equatable, Sendable {
  case bufferOverflow
}

typealias AgentObservationStream = AsyncThrowingStream<ObservedAgentState, Error>
