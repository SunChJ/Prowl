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

  func testTabParsesProfileLaunchAndBackground() throws {
    let command = try CreateTabCommand.parse(["App", "--profile", "Reviewer", "--background"])
    let input = try command.makeInput()

    XCTAssertEqual(input.launch, CreateLaunchInput(profile: "Reviewer"))
    XCTAssertTrue(input.background)
  }

  func testPaneParsesProfileLaunchAndBackground() throws {
    let command = try CreatePaneCommand.parse([
      "p12", "--direction", "right", "--profile", "Reviewer", "--background",
    ])
    let input = try command.makeInput()

    XCTAssertEqual(input.launch, CreateLaunchInput(profile: "Reviewer"))
    XCTAssertTrue(input.background)
  }

  func testPromptAcceptsOnlyTheStdinSentinel() throws {
    let inline = try CreateTabCommand.parse(["App", "--profile", "Reviewer", "--prompt", "inline"])

    XCTAssertThrowsError(try inline.makeInput())
  }

  func testPromptRejectsInteractiveStdinWithoutReading() {
    var options = CreateLaunchOptions()
    options.profile = "Reviewer"
    options.prompt = "-"
    var didRead = false

    XCTAssertThrowsError(
      try options.resolve(
        stdinIsTerminal: true,
        readStdin: {
          didRead = true
          return Data()
        }
      )
    ) { error in
      XCTAssertEqual((error as? ExitError)?.code, CLIErrorCode.invalidArgument)
    }
    XCTAssertFalse(didRead)
  }

  func testPromptAndBackgroundRequireAProfile() throws {
    let prompt = try CreateTabCommand.parse(["App", "--prompt", "-"])
    let background = try CreatePaneCommand.parse(["p12", "--direction", "right", "--background"])

    XCTAssertThrowsError(try prompt.makeInput())
    XCTAssertThrowsError(try background.makeInput())
  }
}
