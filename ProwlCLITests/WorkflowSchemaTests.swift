import Foundation
import JSONSchema
import ProwlCLIContracts
import ProwlCLIShared
import XCTest
import Yams

final class WorkflowSchemaTests: XCTestCase {
  // MARK: - CLI output contract (prowl.cli.workflow.v1)

  func testOutputSchemaAcceptsEveryAction() throws {
    let entry =
      #"{"id":"demo","name":"Demo","description":"d","scope":"user","path":"/Users/me/.prowl/workflows/demo.yaml","enabled":true,"valid":true,"errors":0,"warnings":1,"shadowed":false}"#
    let unparsed =
      #"{"scope":"repo","path":"/Projects/App/.prowl/workflows/broken.yaml","enabled":false,"valid":false,"errors":1,"warnings":0,"shadowed":false}"#
    let list =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"list","worktree":{"id":"w","name":"main","path":"/Projects/App","root_path":"/Projects/App"},"sources":{"bundle":"/Applications/Prowl.app/Contents/Resources/workflows","user":"/Users/me/.prowl/workflows","repo":"/Projects/App/.prowl/workflows"},"workflows":[\#(entry),\#(unparsed)]}}"#
    let listWithoutWorktree =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"list","sources":{"user":"/Users/me/.prowl/workflows"},"workflows":[]}}"#
    let validate =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"validate","path":"/x.yaml","valid":true,"workflow":{"id":"demo","name":"Demo"},"diagnostics":[{"severity":"warning","code":"timeout_long","message":"long","line":4,"column":7},{"severity":"warning","code":"skill_unchecked","message":"unchecked"}]}}"#
    let schema =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"schema","schema":{"$id":"x","type":"object"}}}"#
    let error =
      #"{"ok":false,"command":"workflow","schema_version":"prowl.cli.workflow.v1","error":{"code":"WORKFLOW_INVALID","message":"2 error(s).","details":{"action":"validate","path":"/x.yaml","valid":false,"diagnostics":[]}}}"#
    for instance in [list, listWithoutWorktree, validate, schema, error] {
      try assertValidity(instance, expected: true)
    }
  }

  func testOutputSchemaRejectsUnknownFieldsBadScopesAndCrossActionFields() throws {
    let unknownField =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"list","sources":{"user":"/u"},"workflows":[],"extra":1}}"#
    let badScope =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"list","sources":{"user":"/u"},"workflows":[{"scope":"global","path":"/p","enabled":true,"valid":true,"errors":0,"warnings":0,"shadowed":false}]}}"#
    let crossAction =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"schema","schema":{},"workflows":[]}}"#
    let badSeverity =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v1","data":{"action":"validate","path":"/x","valid":false,"diagnostics":[{"severity":"fatal","code":"c","message":"m"}]}}"#
    let wrongVersion =
      #"{"ok":true,"command":"workflow","schema_version":"prowl.cli.workflow.v2","data":{"action":"schema","schema":{}}}"#
    for instance in [unknownField, badScope, crossAction, badSeverity, wrongVersion] {
      try assertValidity(instance, expected: false)
    }
  }

  func testPayloadRoundTripsThroughCodableWithTheActionDiscriminator() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let validate = WorkflowCommandPayload.validate(
      WorkflowValidatePayload(
        path: "/x.yaml", valid: false, workflow: WorkflowIdentity(id: "demo", name: "Demo"),
        diagnostics: [
          WorkflowDiagnosticPayload(severity: .error, code: "undefined_role", message: "Role 'x'", line: 3, column: 5)
        ]))
    let data = try encoder.encode(validate)
    XCTAssertTrue(String(decoding: data, as: UTF8.self).hasPrefix(#"{"action":"validate""#))
    XCTAssertEqual(try JSONDecoder().decode(WorkflowCommandPayload.self, from: data), validate)

    let list = WorkflowCommandPayload.list(
      WorkflowListPayload(worktree: nil, sources: WorkflowListSources(bundle: nil, user: "/u", repo: nil), workflows: []))
    XCTAssertEqual(
      String(decoding: try encoder.encode(list), as: UTF8.self),
      #"{"action":"list","sources":{"user":"/u"},"workflows":[]}"#)
    let schema = WorkflowCommandPayload.schema(WorkflowSchemaPayload(schema: RawJSON(Data(#"{"type":"object"}"#.utf8))))
    XCTAssertEqual(try JSONDecoder().decode(WorkflowCommandPayload.self, from: try encoder.encode(schema)), schema)
  }

  // MARK: - Workflow definition schema

  func testDefinitionSchemaResourceMatchesTheSwiftConstant() throws {
    let resource = try JSONSerialization.jsonObject(with: ProwlCLIContractBundle.workflowDefinitionSchemaData)
    let constant = try WorkflowJSONSchema.definitionSchemaObject()
    XCTAssertEqual(resource as? NSDictionary, constant as NSDictionary)
    XCTAssertEqual(constant["$id"] as? String, WorkflowJSONSchema.identifier)
  }

  func testDefinitionSchemaAcceptsTheSpecExampleAndRejectsStructuralErrors() throws {
    try assertDefinitionValidity(WorkflowFixtures.adversarialReview, expected: true)
    try assertDefinitionValidity(WorkflowFixtures.minimal(), expected: true)

    let unknownKey = WorkflowFixtures.minimal() + "bogus: 1\n"
    let twoVerbs = WorkflowFixtures.minimal(extraSteps: "  - id: b\n    notify: x\n    close: author")
    let headless = WorkflowFixtures.minimal(extraRoles: "  r:\n    source: launch\n    kind: headless")
    let badMax = WorkflowFixtures.minimal(
      extraSteps: "  - id: loop\n    repeat: { max: 21 }\n    steps:\n      - id: x\n        notify: hi")
    let launchInLoop = WorkflowFixtures.minimal(
      extraSteps: "  - id: loop\n    repeat: { max: 2 }\n    steps:\n      - id: l\n        launch: r\n        prompt: go",
      extraRoles: "  r:\n    source: launch")
    let orphanPolicy = WorkflowFixtures.minimal(
      extraSteps: "  - id: b\n    message: author\n    text: hi\n    expect: { on_timeout: skip }")
    for (name, yaml) in [
      ("unknownKey", unknownKey), ("twoVerbs", twoVerbs), ("headless", headless), ("badMax", badMax),
      ("launchInLoop", launchInLoop), ("orphanPolicy", orphanPolicy),
    ] {
      try assertDefinitionValidity(yaml, expected: false, name)
    }
  }

  // MARK: - Helpers

  private func assertValidity(_ instance: String, expected: Bool) throws {
    let schemaText = try XCTUnwrap(String(data: ProwlCLIContractBundle.schemaData, encoding: .utf8))
    let result = try Schema(instance: schemaText).validate(instance: instance)
    XCTAssertEqual(result.isValid, expected, "Schema errors for \(instance): \(result.errors ?? [])")
  }

  private func assertDefinitionValidity(_ yaml: String, expected: Bool, _ name: String = "") throws {
    let object = try XCTUnwrap(Yams.load(yaml: yaml))
    let json = try JSONSerialization.data(withJSONObject: object)
    let result = try Schema(instance: WorkflowJSONSchema.definitionSchemaJSON)
      .validate(instance: String(decoding: json, as: UTF8.self))
    XCTAssertEqual(result.isValid, expected, "\(name): \(result.errors ?? [])")
  }
}
