import Foundation
import ProwlCLIShared
import XCTest

@testable import prowl

final class AgentSignalOutputRendererTests: XCTestCase {
  func testTextReceiptNamesEventAndPaneWithoutEchoingDetail() {
    let payload = AgentSignalCommandPayload(
      pane: AgentSignalPanePayload(id: "pane-1", worktreeID: "wt-1"),
      signal: AgentSignalPayload(
        event: .turnEnded,
        progress: nil,
        source: "cooperative_cli",
        confidence: "exact",
        timestamp: "1970-01-01T00:16:40.000Z",
        sessionID: "session-1",
        detail: "sensitive result",
        claimedOrigin: nil
      )
    )

    XCTAssertEqual(
      OutputRenderer.agentSignalText(payload),
      "Signaled turn-ended for pane pane-1."
    )
  }

  func testProgressReceiptIncludesValue() {
    let payload = AgentSignalCommandPayload(
      pane: AgentSignalPanePayload(id: "pane-1", worktreeID: "wt-1"),
      signal: AgentSignalPayload(
        event: .progress,
        progress: 75,
        source: "cooperative_cli",
        confidence: "exact",
        timestamp: "1970-01-01T00:16:40.000Z",
        sessionID: nil,
        detail: nil,
        claimedOrigin: nil
      )
    )

    XCTAssertEqual(
      OutputRenderer.agentSignalText(payload),
      "Signaled progress=75 for pane pane-1."
    )
  }
}
