import Foundation
import Testing

@testable import supacode

/// S3b decodes Copilot, Droid, and Qoder through the Claude-shaped path. Their real
/// payloads were captured from Copilot CLI 1.0.80, Factory Droid 0.202.0, and Qoder CLI
/// 1.1.29 (docs-ai 064.008).
struct AgentS3bHookPayloadTests {
  private static let s3bRuntimes: [AgentNativeHookRuntime] = [.copilot, .droid, .qoder]

  @Test func s3bRuntimesShareTheClaudeShapedLifecycleMapping() throws {
    let cases: [(String, AgentSignalEvent)] = [
      ("SessionStart", .sessionStart),
      ("Stop", .turnEnded),
      ("SessionEnd", .sessionEnd),
    ]

    for runtime in Self.s3bRuntimes {
      for (nativeEvent, expected) in cases {
        let payload = Data(
          """
          {
            "hook_event_name": "\(nativeEvent)",
            "session_id": "session-123",
            "cwd": "/tmp/Project Space/界",
            "transcript_path": "/tmp/transcript.jsonl",
            "last_assistant_message": "must not cross the bridge",
            "future_field": {"accepted": true},
            "reason": "complete"
          }
          """.utf8
        )
        let signal = try AgentNativeHookDecoder.decode(
          runtime: runtime,
          nativeEvent: nativeEvent,
          payload: payload
        )

        #expect(signal.event == expected)
        #expect(signal.nativeEvent == nativeEvent)
        #expect(signal.sessionID == "session-123")
        #expect(signal.cwd == "/tmp/Project Space/界")
        #expect(signal.detail != "must not cross the bridge")
      }
    }
  }

  /// Copilot's PascalCase config yields snake_case payloads for lifecycle events but a
  /// mixed-case `Notification`: `hook_event_name` alongside a camelCase `sessionId`. It is
  /// Copilot's only needs-input source, so insisting on `session_id` would silently drop it.
  @Test func copilotNotificationCarriesCamelCaseSessionIdentifier() throws {
    let payload = Data(
      """
      {
        "sessionId": "ef7be551-f465-4de3-99bd-e17facff032d",
        "timestamp": "1787617986906",
        "cwd": "/tmp/project",
        "message": "Run command: touch notifprobe.txt",
        "title": "Permission needed",
        "hook_event_name": "Notification",
        "notification_type": "permission_prompt"
      }
      """.utf8
    )
    let signal = try AgentNativeHookDecoder.decode(
      runtime: .copilot,
      nativeEvent: "Notification",
      payload: payload
    )

    #expect(signal.event == .needsInput)
    #expect(signal.sessionID == "ef7be551-f465-4de3-99bd-e17facff032d")
    #expect(signal.detail == "permission_prompt")
  }

  @Test func s3bNotificationsAcceptOnlyBlockingAttentionTypes() throws {
    for runtime in Self.s3bRuntimes {
      for accepted in ["permission_prompt", "elicitation_dialog"] {
        let signal = try AgentNativeHookDecoder.decode(
          runtime: runtime,
          nativeEvent: "Notification",
          payload: Data(
            """
            {"hook_event_name":"Notification","session_id":"s","cwd":"/tmp",
             "notification_type":"\(accepted)","message":"needs you"}
            """.utf8
          )
        )
        #expect(signal.event == .needsInput)
        #expect(signal.detail == accepted)
      }

      // `idle_prompt` means "waiting", not "blocked on a human", and `auth_success` is
      // informational. Neither may resolve a wait as needs-input.
      for rejected in ["idle_prompt", "auth_success", "shell_completed", "agent_idle"] {
        #expect(throws: AgentNativeHookDecodeError.unsupportedEvent) {
          try AgentNativeHookDecoder.decode(
            runtime: runtime,
            nativeEvent: "Notification",
            payload: Data(
              """
              {"hook_event_name":"Notification","session_id":"s","cwd":"/tmp",
               "notification_type":"\(rejected)"}
              """.utf8
            )
          )
        }
      }
    }
  }

  /// Copilot and Qoder emit `PermissionRequest` even when the permission service
  /// auto-approves and no human is waiting (docs-ai 064.008), so it is never decoded.
  @Test func s3bRuntimesRejectPermissionRequestEntirely() {
    for runtime in Self.s3bRuntimes {
      for nativeEvent in ["PermissionRequest", "PermissionDenied", "Elicitation"] {
        #expect(throws: AgentNativeHookDecodeError.unsupportedEvent) {
          try AgentNativeHookDecoder.decode(
            runtime: runtime,
            nativeEvent: nativeEvent,
            payload: Data(
              """
              {"hook_event_name":"\(nativeEvent)","session_id":"s","cwd":"/tmp","tool_name":"Bash"}
              """.utf8
            )
          )
        }
      }
    }
  }

  @Test func onlyQoderReportsStopFailureAsTurnEnded() throws {
    let payload = Data(
      """
      {"hook_event_name":"StopFailure","session_id":"s","cwd":"/tmp","error_type":"unknown"}
      """.utf8
    )

    let qoder = try AgentNativeHookDecoder.decode(
      runtime: .qoder,
      nativeEvent: "StopFailure",
      payload: payload
    )
    #expect(qoder.event == .turnEnded)

    for runtime in [AgentNativeHookRuntime.copilot, .droid] {
      #expect(throws: AgentNativeHookDecodeError.unsupportedEvent) {
        try AgentNativeHookDecoder.decode(runtime: runtime, nativeEvent: "StopFailure", payload: payload)
      }
    }
  }

  @Test func s3bRuntimesFailClosedOnMismatchedAndInvalidPayloads() {
    for runtime in Self.s3bRuntimes {
      #expect(throws: AgentNativeHookDecodeError.eventMismatch) {
        try AgentNativeHookDecoder.decode(
          runtime: runtime,
          nativeEvent: "Stop",
          payload: Data(#"{"hook_event_name":"SessionEnd","session_id":"s","cwd":"/tmp"}"#.utf8)
        )
      }
      #expect(throws: AgentNativeHookDecodeError.malformedPayload) {
        try AgentNativeHookDecoder.decode(
          runtime: runtime,
          nativeEvent: "Stop",
          payload: Data(#"{"session_id":"s","cwd":"/tmp"}"#.utf8)
        )
      }
      // A relative cwd cannot be compared against the registered launch directory.
      #expect(throws: AgentNativeHookDecodeError.invalidField) {
        try AgentNativeHookDecoder.decode(
          runtime: runtime,
          nativeEvent: "Stop",
          payload: Data(#"{"hook_event_name":"Stop","session_id":"s","cwd":"relative/path"}"#.utf8)
        )
      }
      #expect(throws: AgentNativeHookDecodeError.unsupportedEvent) {
        try AgentNativeHookDecoder.decode(
          runtime: runtime,
          nativeEvent: "SubagentStop",
          payload: Data(#"{"hook_event_name":"SubagentStop","session_id":"s","cwd":"/tmp"}"#.utf8)
        )
      }
    }
  }

  @Test func runtimeRawValuesMatchProfileRuntimesSoObservationCanConvertThem() {
    for runtime in AgentNativeHookRuntime.allCases {
      #expect(
        AgentProfileRuntime(rawValue: runtime.rawValue) != nil,
        "\(runtime.rawValue) must round-trip into AgentProfileRuntime"
      )
    }
    #expect(AgentNativeHookRuntime.qoder.rawValue == "qodercli")
    #expect(AgentProfileRuntime.qoder.rawValue == "qodercli")
  }
}
