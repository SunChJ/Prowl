// supacode/Domain/Workflow/WorkflowTemplateRenderer.swift
// Substitution of the dsl-spec §6 whitelist over a typed context. Substituted values are never
// re-scanned, and a reference to a skipped output is the runtime side of the §5 Skip rule.

import Foundation

nonisolated struct WorkflowTemplateContext: Equatable, Sendable {
  struct Run: Equatable, Sendable {
    let id: String
    let directory: String
  }

  struct Worktree: Equatable, Sendable {
    let path: String
    let name: String
    let branch: String
  }

  struct Role: Equatable, Sendable {
    let name: String
    let agent: String
    /// The pane short handle (`p12`); nil until a launch role is launched.
    let pane: String?
  }

  struct Output: Equatable, Sendable {
    let path: String
    let verdict: String?
  }

  struct Loop: Equatable, Sendable {
    /// 1-based iteration; nil outside a `repeat`.
    let index: Int?
    /// Iterations completed by the latest loop.
    let count: Int
  }

  var run: Run
  var worktree: Worktree
  var roles: [String: Role]
  /// Latest delivered output per name.
  var outputs: [String: Output]
  var skippedOutputs: Set<String>
  var actions: [String: [String: String]]
  var inputs: [String: String]
  var loop: Loop

  init(
    run: Run,
    worktree: Worktree,
    roles: [String: Role],
    outputs: [String: Output],
    skippedOutputs: Set<String> = [],
    actions: [String: [String: String]] = [:],
    inputs: [String: String] = [:],
    loop: Loop = Loop(index: nil, count: 0)
  ) {
    self.run = run
    self.worktree = worktree
    self.roles = roles
    self.outputs = outputs
    self.skippedOutputs = skippedOutputs
    self.actions = actions
    self.inputs = inputs
    self.loop = loop
  }
}

nonisolated enum WorkflowTemplateError: Error, Equatable, Sendable {
  case malformed(WorkflowTemplate.ScanError)
  case unknownVariable(String)
  /// The output was skipped or never delivered: the consumer cannot render (§5 Skip rule).
  case missingOutput(name: String)
  case verdictUnavailable(output: String)
  case paneUnavailable(role: String)
}

extension WorkflowTemplate {
  nonisolated static func render(_ text: String, context: WorkflowTemplateContext) throws(WorkflowTemplateError) -> String {
    guard containsReference(text) else { return text }
    let references: [Reference]
    do {
      references = try Self.references(in: text)
    } catch {
      throw .malformed(error)
    }
    var rendered = ""
    var remainder = Substring(text)
    for reference in references {
      guard let range = remainder.firstRange(of: "{{"),
        let close = remainder[range.upperBound...].firstRange(of: "}}")
      else { break }
      rendered += remainder[..<range.lowerBound]
      rendered += try value(for: reference, context: context)
      remainder = remainder[close.upperBound...]
    }
    rendered += remainder
    return rendered
  }

  nonisolated static func value(for reference: Reference, context: WorkflowTemplateContext) throws(WorkflowTemplateError) -> String {
    let parts = reference.components
    switch (parts.first, parts.count) {
    case ("run", 2):
      switch parts[1] {
      case "id": return context.run.id
      case "dir": return context.run.directory
      default: break
      }
    case ("worktree", 2):
      switch parts[1] {
      case "path": return context.worktree.path
      case "name": return context.worktree.name
      case "branch": return context.worktree.branch
      default: break
      }
    case ("inputs", 2):
      if let value = context.inputs[parts[1]] { return value }
    case ("loop", 2):
      switch parts[1] {
      case "index":
        if let index = context.loop.index { return String(index) }
      case "count":
        return String(context.loop.count)
      default: break
      }
    case ("roles", 3):
      if let role = context.roles[parts[1]] {
        switch parts[2] {
        case "name": return role.name
        case "agent": return role.agent
        case "pane":
          guard let pane = role.pane else { throw .paneUnavailable(role: parts[1]) }
          return pane
        default: break
        }
      }
    case ("outputs", 3):
      guard ["path", "verdict"].contains(parts[2]) else { break }
      guard !context.skippedOutputs.contains(parts[1]), let output = context.outputs[parts[1]] else {
        throw .missingOutput(name: parts[1])
      }
      if parts[2] == "path" { return output.path }
      guard let verdict = output.verdict else { throw .verdictUnavailable(output: parts[1]) }
      return verdict
    case ("actions", 3):
      if let value = context.actions[parts[1]]?[parts[2]] { return value }
    default:
      break
    }
    throw .unknownVariable(reference.path)
  }
}
