import ProwlCLIShared
import XCTest

@testable import prowl

final class CreateCommandParsingTests: XCTestCase {
  func testPaneParsesPositionalAnchorAndDirection() throws {
    let command = try CreatePaneCommand.parse(["p12", "--direction", "up"])

    XCTAssertEqual(try command.makeInput().selector, .pane("p12"))
    XCTAssertEqual(try command.makeInput().direction, .upward)
  }

  func testPaneParsesTypedAnchorAndDirection() throws {
    let anchor = UUID().uuidString
    let command = try CreatePaneCommand.parse(["--pane", anchor, "--direction", "left"])

    XCTAssertEqual(try command.makeInput().selector, .pane(anchor))
    XCTAssertEqual(try command.makeInput().direction, .left)
  }

  func testPaneRequiresDirection() {
    XCTAssertThrowsError(try CreatePaneCommand.parse(["p12"]))
  }

  func testPaneRejectsNonPaneSelectors() throws {
    let worktree = try CreatePaneCommand.parse(["--worktree", "App", "--direction", "right"])
    let tab = try CreatePaneCommand.parse(["--tab", "t4", "--direction", "right"])

    XCTAssertThrowsError(try worktree.makeInput())
    XCTAssertThrowsError(try tab.makeInput())
    XCTAssertThrowsError(try CreatePaneCommand.parse(["--target", "p12", "--direction", "right"]))
  }

  func testPaneRejectsAmbiguousAndInvalidAnchors() throws {
    let mixed = try CreatePaneCommand.parse(["p12", "--pane", "p13", "--direction", "down"])
    let bareNumber = try CreatePaneCommand.parse(["12", "--direction", "down"])

    XCTAssertThrowsError(try mixed.makeInput())
    XCTAssertThrowsError(try bareNumber.makeInput())
  }
}
