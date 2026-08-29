import Foundation
import Testing

@testable import supacode

struct WorkflowDeliveryValidatorTests {
  private let limits = WorkflowDeliveryLimits()

  private func validate(
    _ body: String,
    verdict: String? = nil,
    expect: WorkflowExpectation = WorkflowExpectation(),
    limits: WorkflowDeliveryLimits? = nil
  ) -> Result<WorkflowValidatedDelivery, WorkflowDeliveryError> {
    WorkflowDeliveryValidator.validate(body: body, verdict: verdict, expect: expect, limits: limits ?? self.limits)
  }

  @Test func markdownDeliveryIsNormalizedAndSectionsChecked() throws {
    let expect = WorkflowExpectation(sections: ["## Findings", "## Verdict"])
    let body = """
      Sure, here is my review:
      ```markdown
      # Review
      ## Findings
      - none
      ## Verdict
      clean
      ```
      Let me know if you need more.
      """
    let delivery = try validate(body, expect: expect).get()
    #expect(delivery.body == "# Review\n## Findings\n- none\n## Verdict\nclean\n")
    #expect(delivery.verdict == nil)
  }

  @Test func missingSectionIsOutputInvalid() {
    let expect = WorkflowExpectation(sections: ["## Findings", "## Verdict"])
    guard case .failure(let error) = validate("## Findings\nnothing", expect: expect) else {
      Issue.record("expected failure")
      return
    }
    #expect(error.code == "OUTPUT_INVALID")
    #expect(error.message.contains("## Verdict"))
  }

  @Test func emptyBodyIsOutputInvalidForEveryFormat() {
    for format in [WorkflowOutputFormat.markdown, .text, .json] {
      guard case .failure(let error) = validate("  \n\n", expect: WorkflowExpectation(format: format)) else {
        Issue.record("expected failure for \(format)")
        continue
      }
      #expect(error.code == "OUTPUT_INVALID")
    }
  }

  @Test func textIsKeptVerbatimAndJSONMustParse() throws {
    let text = try validate("  raw text\nwith lines  ", expect: WorkflowExpectation(format: .text)).get()
    #expect(text.body == "  raw text\nwith lines  ")

    let json = try validate("{\"ok\": true}\n", expect: WorkflowExpectation(format: .json)).get()
    #expect(json.body == "{\"ok\": true}\n")
    guard case .failure(let error) = validate("{not json", expect: WorkflowExpectation(format: .json)) else {
      Issue.record("expected failure")
      return
    }
    #expect(error.code == "OUTPUT_INVALID")
  }

  @Test func verdictRulesFollowTheDeclaration() throws {
    let declared = WorkflowExpectation(verdict: ["clean", "issues"])
    guard case .failure(let required) = validate("# ok\n", expect: declared) else {
      Issue.record("expected VERDICT_REQUIRED")
      return
    }
    #expect(required == .verdictRequired(allowed: ["clean", "issues"]))
    #expect(required.code == "VERDICT_REQUIRED")

    guard case .failure(let undeclared) = validate("# ok\n", verdict: "maybe", expect: declared) else {
      Issue.record("expected OUTPUT_INVALID")
      return
    }
    #expect(undeclared.code == "OUTPUT_INVALID")

    let accepted = try validate("# ok\n", verdict: "issues", expect: declared).get()
    #expect(accepted.verdict == "issues")

    guard case .failure(let unexpected) = validate("# ok\n", verdict: "clean", expect: WorkflowExpectation()) else {
      Issue.record("expected OUTPUT_INVALID for an undeclared verdict")
      return
    }
    #expect(unexpected.code == "OUTPUT_INVALID")
  }

  @Test func sizeCapsUseTheDefaultAndClampToTheHardMaximum() {
    #expect(WorkflowDeliveryLimits.defaultMaximumBytes == 1 << 20)
    #expect(WorkflowDeliveryLimits.hardMaximumBytes == 4 << 20)
    #expect(WorkflowDeliveryLimits(maximumBytes: 10 << 20).maximumBytes == 4 << 20)
    #expect(WorkflowDeliveryLimits(maximumBytes: 0).maximumBytes == 1)

    let tooBig = "# a\n" + String(repeating: "x", count: 1 << 20)
    guard case .failure(let error) = validate(tooBig) else {
      Issue.record("expected OUTPUT_TOO_LARGE")
      return
    }
    #expect(error.code == "OUTPUT_TOO_LARGE")
    #expect(error == .outputTooLarge(bytes: tooBig.utf8.count, limit: 1 << 20))

    let raised = WorkflowDeliveryLimits(maximumBytes: 2 << 20)
    #expect(throws: Never.self) { try validate(tooBig, limits: raised).get() }
  }

  @Test func sizeIsMeasuredOnTheRawBodyBeforeNormalization() {
    let expect = WorkflowExpectation(format: .markdown)
    let preamble = String(repeating: "p", count: (1 << 20) - 5)
    let body = preamble + "\n# ok\n"
    guard case .failure(let error) = validate(body, expect: expect) else {
      Issue.record("expected OUTPUT_TOO_LARGE")
      return
    }
    #expect(error.code == "OUTPUT_TOO_LARGE")
  }
}
