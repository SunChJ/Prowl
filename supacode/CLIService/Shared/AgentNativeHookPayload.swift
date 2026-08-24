import Foundation

nonisolated public enum AgentNativeHookRuntime: String, Codable, CaseIterable, Sendable {
  case claude
  case codex
}

nonisolated public struct AgentNativeHookSignal: Codable, Equatable, Sendable {
  public let event: AgentSignalEvent
  public let nativeEvent: String
  public let cwd: String
  public let sessionID: String
  public let detail: String?

  enum CodingKeys: String, CodingKey {
    case event
    case nativeEvent = "native_event"
    case cwd
    case sessionID = "session_id"
    case detail
  }

  public init(
    event: AgentSignalEvent,
    nativeEvent: String,
    cwd: String,
    sessionID: String,
    detail: String? = nil
  ) {
    self.event = event
    self.nativeEvent = nativeEvent
    self.cwd = cwd
    self.sessionID = sessionID
    self.detail = detail
  }
}

nonisolated public struct AgentNativeHookInput: Codable, Equatable, Sendable {
  public static let tokenEnvironmentKey = "PROWL_AGENT_HOOK_TOKEN"
  public static let forwardRecordEnvironmentKey = "PROWL_AGENT_HOOK_FORWARD_RECORD"
  public static let maximumTokenBytes = 256

  public let runtime: AgentNativeHookRuntime
  public let token: String
  public let signal: AgentNativeHookSignal

  public init(runtime: AgentNativeHookRuntime, token: String, signal: AgentNativeHookSignal) {
    self.runtime = runtime
    self.token = token
    self.signal = signal
  }

  public var validationErrorMessage: String? {
    guard !token.isEmpty, token.utf8.count <= Self.maximumTokenBytes,
      !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else {
      return "The managed hook token is invalid."
    }
    return nil
  }
}

nonisolated public enum AgentNativeHookDecodeError: Error, Equatable, Sendable {
  case payloadTooLarge
  case malformedPayload
  case unsupportedEvent
  case eventMismatch
  case invalidField
}

nonisolated public enum AgentNativeHookDecoder {
  public static let maximumPayloadBytes = 1_024 * 1_024
  private static let maximumCWDBytes = 4 * 1_024
  private static let acceptedClaudeNotifications: Set<String> = [
    "elicitation_dialog",
    "idle_prompt",
    "permission_prompt",
  ]

  public static func decode(
    runtime: AgentNativeHookRuntime,
    nativeEvent: String,
    payload: Data
  ) throws -> AgentNativeHookSignal {
    guard payload.count <= maximumPayloadBytes else { throw AgentNativeHookDecodeError.payloadTooLarge }
    guard
      let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    else {
      throw AgentNativeHookDecodeError.malformedPayload
    }
    return switch runtime {
    case .claude:
      try decodeClaude(nativeEvent: nativeEvent, object: object)
    case .codex:
      try decodeCodex(nativeEvent: nativeEvent, object: object)
    }
  }

  private static func decodeClaude(
    nativeEvent: String,
    object: [String: Any]
  ) throws -> AgentNativeHookSignal {
    guard let payloadEvent = object["hook_event_name"] as? String else {
      throw AgentNativeHookDecodeError.malformedPayload
    }
    guard payloadEvent == nativeEvent else { throw AgentNativeHookDecodeError.eventMismatch }
    let event: AgentSignalEvent
    let detail: String?
    switch nativeEvent {
    case "SessionStart":
      event = .sessionStart
      detail = nil
    case "Stop", "StopFailure":
      event = .turnEnded
      detail = boundedOptionalString(object["reason"])
    case "PermissionRequest", "Elicitation":
      event = .needsInput
      detail = boundedOptionalString(object["tool_name"] ?? object["reason"])
    case "Notification":
      guard let type = object["notification_type"] as? String,
        acceptedClaudeNotifications.contains(type)
      else {
        throw AgentNativeHookDecodeError.unsupportedEvent
      }
      event = .needsInput
      detail = type
    case "SessionEnd":
      event = .sessionEnd
      detail = boundedOptionalString(object["reason"])
    default:
      throw AgentNativeHookDecodeError.unsupportedEvent
    }
    return try makeSignal(
      event: event,
      nativeEvent: nativeEvent,
      cwd: object["cwd"],
      sessionID: object["session_id"],
      detail: detail
    )
  }

  private static func decodeCodex(
    nativeEvent: String,
    object: [String: Any]
  ) throws -> AgentNativeHookSignal {
    guard nativeEvent == "agent-turn-complete" else {
      throw AgentNativeHookDecodeError.unsupportedEvent
    }
    guard let payloadEvent = object["type"] as? String else {
      throw AgentNativeHookDecodeError.malformedPayload
    }
    guard payloadEvent == nativeEvent else { throw AgentNativeHookDecodeError.eventMismatch }
    return try makeSignal(
      event: .turnEnded,
      nativeEvent: nativeEvent,
      cwd: object["cwd"],
      sessionID: object["thread-id"],
      detail: nil
    )
  }

  private static func makeSignal(
    event: AgentSignalEvent,
    nativeEvent: String,
    cwd: Any?,
    sessionID: Any?,
    detail: String?
  ) throws -> AgentNativeHookSignal {
    guard let cwd = cwd as? String, isValid(cwd, maximumBytes: maximumCWDBytes), cwd.hasPrefix("/") else {
      throw AgentNativeHookDecodeError.invalidField
    }
    guard let sessionID = sessionID as? String,
      isValid(sessionID, maximumBytes: AgentSignalInput.maximumSessionIDBytes)
    else {
      throw AgentNativeHookDecodeError.invalidField
    }
    return AgentNativeHookSignal(
      event: event,
      nativeEvent: nativeEvent,
      cwd: cwd,
      sessionID: sessionID,
      detail: detail
    )
  }

  private static func boundedOptionalString(_ value: Any?) -> String? {
    guard let value = value as? String,
      isValid(value, maximumBytes: AgentSignalInput.maximumDetailBytes)
    else {
      return nil
    }
    return value
  }

  private static func isValid(_ value: String, maximumBytes: Int) -> Bool {
    !value.isEmpty
      && value.utf8.count <= maximumBytes
      && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
  }
}
