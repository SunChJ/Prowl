// ProwlCLI/Output/OutputRenderer+Workflow.swift
// Text rendering for `prowl workflow`.

import Foundation
import ProwlCLIShared
@preconcurrency import Rainbow

extension OutputRenderer {
  static func renderWorkflow(_ payload: WorkflowCommandPayload) {
    switch payload {
    case .list(let list):
      print(workflowListText(list))
    case .validate(let validate):
      print(workflowValidateText(validate))
    case .schema(let schema):
      renderWorkflowSchema(schema)
    }
  }

  static func workflowListText(_ payload: WorkflowListPayload) -> String {
    var lines: [String] = []
    if let worktree = payload.worktree {
      lines.append("Worktree: \(worktree.name.bold)  \(worktree.path.dim)")
    }
    lines.append("Sources: bundle \(payload.sources.bundle ?? "—")  user \(payload.sources.user)  repo \(payload.sources.repo ?? "—")".dim)
    guard !payload.workflows.isEmpty else {
      lines.append("No workflow definitions found.")
      return lines.joined(separator: "\n")
    }
    lines.append("")
    for entry in payload.workflows {
      let id = entry.id ?? "(unparsed)"
      let name = entry.name.map { "  \($0)" } ?? ""
      var flags: [String] = []
      flags.append(entry.valid ? "valid".green : "invalid".red)
      if entry.warnings > 0 { flags.append("\(entry.warnings) warning(s)".yellow) }
      if entry.errors > 0 { flags.append("\(entry.errors) error(s)".red) }
      if !entry.enabled { flags.append("disabled".dim) }
      if entry.shadowed { flags.append("shadowed".dim) }
      lines.append("\(id.bold)\(name)  [\(entry.scope.rawValue)]  \(flags.joined(separator: "  "))")
      lines.append("  \(entry.path.dim)")
    }
    return lines.joined(separator: "\n")
  }

  static func workflowValidateText(_ payload: WorkflowValidatePayload) -> String {
    var lines = payload.diagnostics.map { diagnostic in
      let position = diagnostic.line.map { line in
        ":\(line)" + (diagnostic.column.map { ":\($0)" } ?? "")
      } ?? ""
      let severity = diagnostic.severity == .error ? "error".red : "warning".yellow
      return "\(payload.path)\(position): \(severity)[\(diagnostic.code)]: \(diagnostic.message)"
    }
    let errors = payload.diagnostics.filter { $0.severity == .error }.count
    let warnings = payload.diagnostics.count - errors
    let identity = payload.workflow.map { "\($0.id) (\($0.name))" } ?? payload.path
    if payload.valid {
      lines.append("\("OK".green)  \(identity)\(warnings > 0 ? "  \(warnings) warning(s)".yellow : "")")
    } else {
      lines.append("\("INVALID".red)  \(identity)  \(errors) error(s), \(warnings) warning(s)")
    }
    return lines.joined(separator: "\n")
  }

  private static func renderWorkflowSchema(_ payload: WorkflowSchemaPayload) {
    if let object = try? JSONSerialization.jsonObject(with: payload.schema.bytes),
      let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    {
      FileHandle.standardOutput.write(pretty)
      FileHandle.standardOutput.write(Data([UInt8(ascii: "\n")]))
      return
    }
    FileHandle.standardOutput.write(payload.schema.bytes)
  }
}
