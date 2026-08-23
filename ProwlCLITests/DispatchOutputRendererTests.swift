import Foundation
import ProwlCLIShared
import XCTest

@testable import prowl

final class DispatchOutputRendererTests: XCTestCase {
  func testCompletionAndAbandonmentReceiptsRenderDeterministically() {
    let completion = DispatchCompleteCommandPayload(
      target: Self.target,
      receipt: DispatchCompletedRecord(
        id: "d1",
        outcome: .succeeded,
        summary: "Implemented and verified.",
        createdAt: "2026-08-23T02:00:00.000Z",
        completedAt: "2026-08-23T02:01:00.000Z"
      ),
      replayed: false
    )
    XCTAssertEqual(
      OutputRenderer.dispatchCompleteText(completion),
      "Completed dispatch d1: succeeded\n  pane: pane\n  summary: Implemented and verified."
    )

    let abandonment = DispatchAbandonCommandPayload(
      target: Self.target,
      record: DispatchAbandonedRecord(
        id: "d2",
        createdAt: "2026-08-23T02:00:00.000Z",
        abandonedAt: "2026-08-23T02:01:00.000Z",
        reason: "Worker stopped reporting"
      ),
      replayed: true
    )
    XCTAssertEqual(
      OutputRenderer.dispatchAbandonText(abandonment),
      "Abandoned dispatch d2 (replayed)\n  pane: pane\n  reason: Worker stopped reporting"
    )
  }

  func testWaitSuccessRendersModeProvenanceAndSummary() {
    let payload = AgentWaitCommandPayload.dispatch(
      AgentDispatchWaitPayload(
        waitedMilliseconds: 125,
        target: Self.target,
        receipt: DispatchCompletedRecord(
          id: "d1",
          outcome: .succeeded,
          summary: "Done",
          createdAt: "2026-08-23T02:00:00.000Z",
          completedAt: "2026-08-23T02:01:00.000Z"
        ),
        signals: AgentSignalsPayload(channels: [], last: nil, lastBinding: nil)
      )
    )

    XCTAssertEqual(
      OutputRenderer.agentWaitText(payload),
      "Dispatch d1 succeeded after 125 ms\n  pane: pane\n  summary: Done"
    )
  }

  func testStructuredWaitFailureTextIncludesLastKnownRecord() throws {
    let details = AgentWaitErrorDetails.dispatch(
      AgentDispatchWaitErrorDetails(
        waitedMilliseconds: 600_000,
        target: Self.target,
        record: .pending(
          DispatchPendingRecord(id: "d1", createdAt: "2026-08-23T02:00:00.000Z")
        )
      )
    )
    let error = CommandError(
      code: "WAIT_TIMEOUT",
      message: "Timed out.",
      details: try RawJSON(encoding: details)
    )

    XCTAssertEqual(
      OutputRenderer.errorText(error, command: "agents.wait"),
      "error [WAIT_TIMEOUT]: Timed out.\n  dispatch: d1 (pending)\n  pane: pane\n  waited: 600000 ms"
    )
  }

  private static let target = TabTarget(
    worktree: TabTargetWorktree(
      id: "wt", name: "main", path: "/Projects/Prowl", rootPath: "/Projects/Prowl", kind: "git"
    ),
    tab: TabTargetTab(id: "tab", title: "Tab", selected: true),
    pane: TabTargetPane(id: "pane", title: "Pane", cwd: "/Projects/Prowl", focused: true)
  )
}
