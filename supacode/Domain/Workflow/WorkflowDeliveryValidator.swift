// supacode/Domain/Workflow/WorkflowDeliveryValidator.swift
// Validation of a `prowl workflow done` body against the step's `expect` (dsl-spec §5): size
// caps, format, required sections, and the verdict declaration.

import Foundation

nonisolated struct WorkflowDeliveryLimits: Equatable, Sendable {
  static let defaultMaximumBytes = 1 << 20
  static let hardMaximumBytes = 4 << 20

  /// Bytes of UTF-8 a delivered body may have; clamped to `1…hardMaximumBytes`.
  let maximumBytes: Int

  init(maximumBytes: Int = Self.defaultMaximumBytes) {
    self.maximumBytes = min(max(1, maximumBytes), Self.hardMaximumBytes)
  }
}

nonisolated enum WorkflowDeliveryError: Error, Equatable, Sendable {
  /// No activation is currently waiting for the caller (or for the addressed step).
  case stepNotExpecting
  case tokenRequired
  case tokenInvalid
  case outputInvalid(reason: String)
  case outputTooLarge(bytes: Int, limit: Int)
  case verdictRequired(allowed: [String])

  var code: String {
    switch self {
    case .stepNotExpecting: CLIErrorCode.stepNotExpecting
    case .tokenRequired: CLIErrorCode.tokenRequired
    case .tokenInvalid: CLIErrorCode.tokenInvalid
    case .outputInvalid: CLIErrorCode.outputInvalid
    case .outputTooLarge: CLIErrorCode.outputTooLarge
    case .verdictRequired: CLIErrorCode.verdictRequired
    }
  }

  var message: String {
    switch self {
    case .stepNotExpecting:
      "No workflow step is waiting for a delivery from this pane."
    case .tokenRequired:
      "The delivery token is missing; run the generated completion command "
        + "(\(WorkflowSchema.tokenEnvironmentKey)=… \(WorkflowCompletionCommand.executable) …)."
    case .tokenInvalid:
      "The delivery token does not belong to the step that is waiting; rerun the latest generated completion command."
    case .outputInvalid(let reason):
      "The delivered output is invalid: \(reason)"
    case .outputTooLarge(let bytes, let limit):
      "The delivered output is \(bytes) bytes; the limit is \(limit) bytes."
    case .verdictRequired(let allowed):
      "This step requires a verdict: pass --verdict with one of \(allowed.joined(separator: ", "))."
    }
  }
}

/// A delivery that passed validation: the body in its persisted form and the accepted verdict.
nonisolated struct WorkflowValidatedDelivery: Equatable, Sendable {
  let body: String
  let verdict: String?
}

nonisolated enum WorkflowDeliveryValidator {
  static func validate(
    body: String,
    verdict: String?,
    expect: WorkflowExpectation,
    limits: WorkflowDeliveryLimits
  ) -> Result<WorkflowValidatedDelivery, WorkflowDeliveryError> {
    let bytes = body.utf8.count
    guard bytes <= limits.maximumBytes else {
      return .failure(.outputTooLarge(bytes: bytes, limit: limits.maximumBytes))
    }
    switch (expect.verdict, verdict) {
    case (nil, nil):
      break
    case (nil, .some):
      return .failure(.outputInvalid(reason: "this step declares no verdict."))
    case (.some(let allowed), nil):
      return .failure(.verdictRequired(allowed: allowed))
    case (.some(let allowed), .some(let value)):
      guard allowed.contains(value) else {
        return .failure(
          .outputInvalid(reason: "verdict '\(value)' is not one of \(allowed.joined(separator: ", "))."))
      }
    }
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.outputInvalid(reason: "the body is empty."))
    }
    switch expect.format {
    case .markdown:
      let normalized = MarkdownArtifactNormalizer.normalized(body)
      guard !normalized.isEmpty else {
        return .failure(.outputInvalid(reason: "the body is empty."))
      }
      let headings = Self.headings(outsideFences: normalized)
      let missing = expect.sections.filter { section in
        let wanted = section.trimmingCharacters(in: .whitespaces)
        return !headings.contains { $0 == wanted || $0.hasPrefix(wanted + " ") }
      }
      guard missing.isEmpty else {
        return .failure(
          .outputInvalid(reason: "missing required section(s): \(missing.joined(separator: ", "))."))
      }
      return .success(WorkflowValidatedDelivery(body: normalized + "\n", verdict: verdict))
    case .text:
      return .success(WorkflowValidatedDelivery(body: body, verdict: verdict))
    case .json:
      do {
        _ = try JSONSerialization.jsonObject(with: Data(body.utf8), options: [.fragmentsAllowed])
      } catch {
        return .failure(.outputInvalid(reason: "the body is not parseable JSON."))
      }
      return .success(WorkflowValidatedDelivery(body: body, verdict: verdict))
    }
  }

  /// Heading lines (`#…`) outside fenced code blocks, trimmed; a heading quoted inside a
  /// fence does not satisfy a required section.
  static func headings(outsideFences text: String) -> [String] {
    var headings: [String] = []
    var fence: String?
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if let open = fence {
        if line.hasPrefix(open) { fence = nil }
        continue
      }
      if line.hasPrefix("```") || line.hasPrefix("~~~") {
        fence = String(line.prefix(3))
        continue
      }
      if line.hasPrefix("#") {
        headings.append(line)
      }
    }
    return headings
  }
}
