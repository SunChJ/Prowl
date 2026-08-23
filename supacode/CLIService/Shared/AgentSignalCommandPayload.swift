import Foundation

public struct AgentSignalCommandPayload: Codable, Equatable, Sendable {
  public let pane: AgentSignalPanePayload
  public let signal: AgentSignalPayload

  public init(pane: AgentSignalPanePayload, signal: AgentSignalPayload) {
    self.pane = pane
    self.signal = signal
  }
}

public struct AgentSignalPanePayload: Codable, Equatable, Sendable {
  public let id: String
  public let worktreeID: String

  enum CodingKeys: String, CodingKey {
    case id
    case worktreeID = "worktree_id"
  }

  public init(id: String, worktreeID: String) {
    self.id = id
    self.worktreeID = worktreeID
  }
}

public struct AgentSignalPayload: Codable, Equatable, Sendable {
  public let event: AgentSignalEvent
  public let progress: Int?
  public let source: String
  public let confidence: String
  public let timestamp: String
  public let sessionID: String?
  public let detail: String?
  public let claimedOrigin: String?

  enum CodingKeys: String, CodingKey {
    case event
    case progress
    case source
    case confidence
    case timestamp = "at"
    case sessionID = "session_id"
    case detail
    case claimedOrigin = "claimed_origin"
  }

  public init(
    event: AgentSignalEvent,
    progress: Int?,
    source: String,
    confidence: String,
    timestamp: String,
    sessionID: String?,
    detail: String?,
    claimedOrigin: String?
  ) {
    self.event = event
    self.progress = progress
    self.source = source
    self.confidence = confidence
    self.timestamp = timestamp
    self.sessionID = sessionID
    self.detail = detail
    self.claimedOrigin = claimedOrigin
  }
}
