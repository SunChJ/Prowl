import ProwlCLIShared
import XCTest

@testable import prowl

final class WorkflowCommandParsingTests: XCTestCase {
  func testRootRoutesWorkflowSubcommands() throws {
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["workflow", "list"]) is WorkflowListCommand)
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["workflow", "validate", "flow.yaml"]) is WorkflowValidateCommand)
    XCTAssertTrue(try ProwlCommand.parseAsRoot(["workflow", "schema"]) is WorkflowSchemaCommand)
  }

  func testListAcceptsAPositionalTargetOrOneSelectorFlag() throws {
    let bare = try WorkflowListCommand.parse(["--json"])
    XCTAssertEqual(try bare.selector.resolve(positionalTarget: bare.target), .none)

    let positional = try WorkflowListCommand.parse(["p3"])
    XCTAssertEqual(try positional.selector.resolve(positionalTarget: positional.target), .auto("p3"))

    let flag = try WorkflowListCommand.parse(["--worktree", "main"])
    XCTAssertEqual(try flag.selector.resolve(positionalTarget: flag.target), .worktree("main"))

    let both = try WorkflowListCommand.parse(["p3", "--worktree", "main"])
    XCTAssertThrowsError(try both.selector.resolve(positionalTarget: both.target)) { error in
      XCTAssertEqual((error as? ExitError)?.code, CLIErrorCode.invalidArgument)
    }
  }

  func testValidateRequiresAFileAndAcceptsAScope() throws {
    let command = try WorkflowValidateCommand.parse(["flows/review.yaml", "--scope", "repo", "--json"])
    XCTAssertEqual(command.file, "flows/review.yaml")
    XCTAssertEqual(command.scope, .repo)
    XCTAssertTrue(command.options.json)
    XCTAssertNil(try WorkflowValidateCommand.parse(["x.yaml"]).scope)
    XCTAssertThrowsError(try WorkflowValidateCommand.parse([]))
    XCTAssertThrowsError(try WorkflowValidateCommand.parse(["x.yaml", "--scope", "global"]))
  }

  func testWorkflowInputEnvelopeEncodesTheTarget() throws {
    let envelope = CommandEnvelope(output: .json, command: .workflow(WorkflowInput(action: .list, target: .auto("p3"))))
    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(CommandEnvelope.self, from: data)
    guard case .workflow(let input) = decoded.command else { return XCTFail("Expected a workflow envelope") }
    XCTAssertEqual(input.action, .list)
    XCTAssertEqual(input.target, .auto("p3"))
    XCTAssertEqual(decoded.command.name, "workflow")
  }
}
