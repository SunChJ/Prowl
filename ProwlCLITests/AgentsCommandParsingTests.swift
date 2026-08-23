import Foundation
import ProwlCLIContracts
import ProwlCLIShared
import XCTest

@testable import prowl

final class AgentsCommandParsingTests: XCTestCase {
  func testListParsesWithoutSubcommand() throws {
    _ = try AgentsCommand.parse([])
  }

  func testReadParsesExplicitPaneAndResultOptions() throws {
    let command = try AgentsReadCommand.parse(["p7", "--max-bytes", "1024", "--result-only"])

    XCTAssertEqual(command.pane, "p7")
    XCTAssertEqual(command.maxBytes, 1024)
    XCTAssertTrue(command.resultOnly)
  }

  func testReadRequiresPaneHandleOrUUID() {
    XCTAssertThrowsError(try AgentsReadCommand.parse(["main"]))
  }

  func testReadRejectsResultOnlyJSONCombination() throws {
    let command = try AgentsReadCommand.parse(["p7", "--result-only", "--json"])

    XCTAssertThrowsError(try command.validateOutputMode())
  }

  func testSignalParsesEventAndMetadata() throws {
    let command = try AgentsSignalCommand.parse([
      "turn-ended",
      "--origin", "manual-review",
      "--session", "session-1",
      "--detail", "Review complete",
      "--json",
    ])

    XCTAssertEqual(command.event, .turnEnded)
    XCTAssertNil(command.progress)
    XCTAssertEqual(command.origin, "manual-review")
    XCTAssertEqual(command.sessionID, "session-1")
    XCTAssertEqual(command.detail, "Review complete")
    XCTAssertTrue(command.options.json)
  }

  func testSignalParsesIndeterminateAndNumericProgress() throws {
    let indeterminate = try AgentsSignalCommand.parse(["progress"])
    let numeric = try AgentsSignalCommand.parse(["progress", "--progress", "75"])

    XCTAssertEqual(indeterminate.event, .progress)
    XCTAssertNil(indeterminate.progress)
    XCTAssertEqual(numeric.progress, 75)
  }

  func testSignalHelpAndSchemaUseSharedDetailLimit() throws {
    XCTAssertTrue(
      AgentsSignalCommand.helpMessage().contains(
        "maximum \(AgentSignalInput.maximumDetailBytes) UTF-8 bytes"
      )
    )

    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: ProwlCLIContractBundle.schemaData) as? [String: Any]
    )
    let definitions = try XCTUnwrap(root["$defs"] as? [String: Any])
    let agentSignalData = try XCTUnwrap(definitions["agentSignalData"] as? [String: Any])
    let dataProperties = try XCTUnwrap(agentSignalData["properties"] as? [String: Any])
    let signal = try XCTUnwrap(dataProperties["signal"] as? [String: Any])
    let signalProperties = try XCTUnwrap(signal["properties"] as? [String: Any])
    let detail = try XCTUnwrap(signalProperties["detail"] as? [String: Any])

    XCTAssertEqual(detail["maxLength"] as? Int, AgentSignalInput.maximumDetailBytes)
  }

  func testSignalRejectsInvalidEventProgressAndBoundedText() {
    XCTAssertThrowsError(try AgentsSignalCommand.parse(["complete"]))
    XCTAssertThrowsError(try AgentsSignalCommand.parse(["turn-ended", "--progress", "1"]))
    XCTAssertThrowsError(try AgentsSignalCommand.parse(["progress", "--progress", "101"]))
    XCTAssertNoThrow(
      try AgentsSignalCommand.parse(["needs-input", "--detail", String(repeating: "x", count: 32_768)])
    )
    XCTAssertNoThrow(
      try AgentsSignalCommand.parse(["needs-input", "--detail", String(repeating: "界", count: 10_922)])
    )
    XCTAssertThrowsError(
      try AgentsSignalCommand.parse(["needs-input", "--detail", String(repeating: "x", count: 32_769)])
    )
    XCTAssertThrowsError(
      try AgentsSignalCommand.parse(["needs-input", "--detail", String(repeating: "界", count: 10_923)])
    )
  }
}
