import Foundation
import Testing

@testable import supacode

struct AgentTranscriptResultReaderTests {
  @Test func decodesLatestClosedCodexTaskCompletion() throws {
    let result = AgentTranscriptResultReader.decode(
      agent: .codex,
      jsonl: try jsonl([
        codexCompletion(turnID: "turn-1", completedAt: "2026-08-11T12:00:00Z", text: "First result"),
        codexCompletion(turnID: "turn-2", completedAt: "2026-08-11T12:01:00Z", text: "Final result"),
      ]),
      maxBytes: 1_024
    )

    #expect(result.state == .complete)
    #expect(result.text == "Final result")
  }

  @Test func reportsCodexMaxTokensAsIncompleteWithoutText() throws {
    let result = AgentTranscriptResultReader.decode(
      agent: .codex,
      jsonl: try jsonl([
        codexCompletion(
          turnID: "turn-1",
          completedAt: "2026-08-11T12:00:00Z",
          text: "Partial result",
          status: "max_tokens"
        )
      ]),
      maxBytes: 1_024
    )

    #expect(result.state == .incomplete)
    #expect(result.text == nil)
  }

  @Test func followsClaudeTurnDurationParentChainToClosedAssistantText() throws {
    let result = AgentTranscriptResultReader.decode(
      agent: .claude,
      jsonl: try jsonl([
        claudeAssistant(uuid: "assistant-1", sessionID: "session-1", text: "Claude final result"),
        claudeSystem(
          subtype: "stop_hook_summary",
          uuid: "summary-1",
          sessionID: "session-1",
          parentUUID: "assistant-1"
        ),
        claudeSystem(
          subtype: "turn_duration",
          uuid: "duration-1",
          sessionID: "session-1",
          parentUUID: "summary-1"
        ),
      ]),
      maxBytes: 1_024
    )

    #expect(result.state == .complete)
    #expect(result.text == "Claude final result")
  }

  @Test func rejectsClaudeToolOnlyAssistantTurnAsIncomplete() throws {
    let result = AgentTranscriptResultReader.decode(
      agent: .claude,
      jsonl: try jsonl([
        claudeAssistant(uuid: "assistant-1", sessionID: "session-1", content: [["type": "tool_use", "name": "Bash"]]),
        claudeSystem(
          subtype: "turn_duration",
          uuid: "duration-1",
          sessionID: "session-1",
          parentUUID: "assistant-1"
        ),
      ]),
      maxBytes: 1_024
    )

    #expect(result.state == .incomplete)
    #expect(result.text == nil)
  }

  @Test func rejectsUnclosedJSONLWithoutReturningPartialText() throws {
    let jsonl =
      try jsonl([
        codexCompletion(turnID: "turn-1", completedAt: "2026-08-11T12:00:00Z", text: "Final result")
      ]) + "{\"type\":\"event_msg\"\n"
    let result = AgentTranscriptResultReader.decode(agent: .codex, jsonl: jsonl, maxBytes: 1_024)

    #expect(result.state == .incomplete)
    #expect(result.text == nil)
  }

  @Test func reportsOversizedCompleteResultWithoutTruncatingIt() throws {
    let result = AgentTranscriptResultReader.decode(
      agent: .codex,
      jsonl: try jsonl([
        codexCompletion(turnID: "turn-1", completedAt: "2026-08-11T12:00:00Z", text: "0123456789")
      ]),
      maxBytes: 5
    )

    #expect(result.state == .tooLarge)
    #expect(result.text == nil)
  }

  @Test func readsOnlyTheBoundedTranscriptTail() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "prowl-result-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    let oversizedHistory =
      "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"text\":\""
      + String(repeating: "x", count: 1_100_000) + "\"}}\n"
    let completion = try jsonl([
      codexCompletion(turnID: "turn-1", completedAt: "2026-08-11T12:00:00Z", text: "Final result")
    ])
    try (oversizedHistory + completion).write(to: url, atomically: true, encoding: .utf8)

    let result = AgentTranscriptResultReader.read(agent: .codex, at: url, maxBytes: 1_024)

    #expect(result.state == .complete)
    #expect(result.text == "Final result")
  }

  private func codexCompletion(
    turnID: String,
    completedAt: String,
    text: String,
    status: String? = nil
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "type": "task_complete",
      "turn_id": turnID,
      "completed_at": completedAt,
      "last_agent_message": text,
    ]
    payload["status"] = status
    return ["type": "event_msg", "payload": payload]
  }

  private func claudeAssistant(
    uuid: String,
    sessionID: String,
    text: String? = nil,
    content: [[String: Any]]? = nil
  ) -> [String: Any] {
    [
      "type": "assistant",
      "uuid": uuid,
      "sessionId": sessionID,
      "message": [
        "stop_reason": "end_turn",
        "content": content ?? [["type": "text", "text": text ?? ""]],
      ],
    ]
  }

  private func claudeSystem(
    subtype: String,
    uuid: String,
    sessionID: String,
    parentUUID: String
  ) -> [String: Any] {
    [
      "type": "system",
      "subtype": subtype,
      "uuid": uuid,
      "sessionId": sessionID,
      "parentUuid": parentUUID,
    ]
  }

  private func jsonl(_ records: [[String: Any]]) throws -> String {
    try records.map { record in
      let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
      return try #require(String(data: data, encoding: .utf8)) + "\n"
    }.joined()
  }
}
