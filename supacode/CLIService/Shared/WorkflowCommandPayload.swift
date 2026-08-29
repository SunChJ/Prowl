// ProwlShared/WorkflowCommandPayload.swift
// `prowl workflow` response data (`prowl.cli.workflow.v1`), discriminated by `action`.
// `list` crosses the socket; `validate` and `schema` are produced locally by the CLI.

import Foundation

nonisolated public enum WorkflowCommandPayload: Codable, Equatable, Sendable {
  public static let schemaVersion = "prowl.cli.workflow.v1"
  public static let commandName = "workflow"

  case list(WorkflowListPayload)
  case validate(WorkflowValidatePayload)
  case schema(WorkflowSchemaPayload)

  public var action: WorkflowCommandAction {
    switch self {
    case .list: .list
    case .validate: .validate
    case .schema: .schema
    }
  }

  private enum CodingKeys: String, CodingKey {
    case action
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(WorkflowCommandAction.self, forKey: .action) {
    case .list: self = .list(try WorkflowListPayload(from: decoder))
    case .validate: self = .validate(try WorkflowValidatePayload(from: decoder))
    case .schema: self = .schema(try WorkflowSchemaPayload(from: decoder))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(action, forKey: .action)
    switch self {
    case .list(let payload): try payload.encode(to: encoder)
    case .validate(let payload): try payload.encode(to: encoder)
    case .schema(let payload): try payload.encode(to: encoder)
    }
  }
}

nonisolated public enum WorkflowCommandAction: String, Codable, Equatable, Sendable {
  case list
  case validate
  case schema
}

// MARK: - list

nonisolated public struct WorkflowListPayload: Codable, Equatable, Sendable {
  /// The worktree whose repo source was searched; absent when no worktree could be resolved.
  public let worktree: WorkflowListWorktree?
  public let sources: WorkflowListSources
  public let workflows: [WorkflowListEntry]

  public init(worktree: WorkflowListWorktree?, sources: WorkflowListSources, workflows: [WorkflowListEntry]) {
    self.worktree = worktree
    self.sources = sources
    self.workflows = workflows
  }
}

nonisolated public struct WorkflowListWorktree: Codable, Equatable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let rootPath: String

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case path
    case rootPath = "root_path"
  }

  public init(id: String, name: String, path: String, rootPath: String) {
    self.id = id
    self.name = name
    self.path = path
    self.rootPath = rootPath
  }
}

/// Directories searched; a nil entry means the source does not apply (no app bundle, no worktree).
nonisolated public struct WorkflowListSources: Codable, Equatable, Sendable {
  public let bundle: String?
  public let user: String
  public let repo: String?

  public init(bundle: String?, user: String, repo: String?) {
    self.bundle = bundle
    self.user = user
    self.repo = repo
  }
}

nonisolated public struct WorkflowListEntry: Codable, Equatable, Sendable {
  /// Absent when the file did not parse.
  public let id: String?
  public let name: String?
  public let description: String?
  public let scope: WorkflowScope
  public let path: String
  public let enabled: Bool
  public let valid: Bool
  public let errors: Int
  public let warnings: Int
  public let shadowed: Bool

  public init(
    id: String?,
    name: String?,
    description: String?,
    scope: WorkflowScope,
    path: String,
    enabled: Bool,
    valid: Bool,
    errors: Int,
    warnings: Int,
    shadowed: Bool
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.scope = scope
    self.path = path
    self.enabled = enabled
    self.valid = valid
    self.errors = errors
    self.warnings = warnings
    self.shadowed = shadowed
  }

  public init(entry: WorkflowCatalogEntry, enabled: Bool) {
    self.init(
      id: entry.file.id,
      name: entry.file.definition?.name,
      description: entry.file.definition?.description,
      scope: entry.file.scope,
      path: entry.file.url.path(percentEncoded: false),
      enabled: enabled,
      valid: entry.file.isValid,
      errors: entry.file.diagnostics.errorCount,
      warnings: entry.file.diagnostics.warningCount,
      shadowed: entry.shadowed
    )
  }
}

// MARK: - validate

nonisolated public struct WorkflowValidatePayload: Codable, Equatable, Sendable {
  public let path: String
  public let valid: Bool
  /// Present when the file parsed, even if validation then failed.
  public let workflow: WorkflowIdentity?
  public let diagnostics: [WorkflowDiagnosticPayload]

  public init(path: String, valid: Bool, workflow: WorkflowIdentity?, diagnostics: [WorkflowDiagnosticPayload]) {
    self.path = path
    self.valid = valid
    self.workflow = workflow
    self.diagnostics = diagnostics
  }

  public init(file: WorkflowSourceFile) {
    self.init(
      path: file.url.path(percentEncoded: false),
      valid: file.isValid,
      workflow: file.definition.map { WorkflowIdentity(id: $0.id, name: $0.name) },
      diagnostics: file.diagnostics.map(WorkflowDiagnosticPayload.init)
    )
  }
}

nonisolated public struct WorkflowIdentity: Codable, Equatable, Sendable {
  public let id: String
  public let name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

nonisolated public struct WorkflowDiagnosticPayload: Codable, Equatable, Sendable {
  public let severity: WorkflowDiagnosticSeverity
  public let code: String
  public let message: String
  public let line: Int?
  public let column: Int?

  public init(severity: WorkflowDiagnosticSeverity, code: String, message: String, line: Int?, column: Int?) {
    self.severity = severity
    self.code = code
    self.message = message
    self.line = line
    self.column = column
  }

  public init(_ diagnostic: WorkflowDiagnostic) {
    self.init(
      severity: diagnostic.severity,
      code: diagnostic.code,
      message: diagnostic.message,
      line: diagnostic.location?.line,
      column: diagnostic.location?.column
    )
  }
}

// MARK: - schema

nonisolated public struct WorkflowSchemaPayload: Codable, Equatable, Sendable {
  /// The Draft 2020-12 JSON Schema of a workflow file, inline.
  public let schema: RawJSON

  public init(schema: RawJSON) {
    self.schema = schema
  }
}

nonisolated extension RawJSON: Equatable {
  public static func == (lhs: RawJSON, rhs: RawJSON) -> Bool {
    lhs.bytes == rhs.bytes
  }
}
