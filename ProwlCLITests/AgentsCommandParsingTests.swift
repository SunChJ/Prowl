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
}
