// ProwlCLI/Commands/WorkflowCommand.swift
// `prowl workflow`: definitions discovery and authoring support (docs-ai 063 B1).
// `list` asks the running app; `validate` and `schema` run locally and never open the socket.

import ArgumentParser
import Foundation
import ProwlCLIShared

struct WorkflowCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "workflow",
    abstract: "Discover, validate, and describe Agent Workflow definitions.",
    discussion: """
      Definitions are YAML files (`prowl.workflow/v1`) found in the app bundle, ~/.prowl/workflows, \
      and <repo>/.prowl/workflows. `validate` and `schema` work with Prowl closed; `list` needs the app.
      """,
    subcommands: [
      WorkflowListCommand.self,
      WorkflowValidateCommand.self,
      WorkflowSchemaCommand.self,
    ]
  )
}

struct WorkflowListCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List the workflow definitions visible to a worktree, with validation status."
  )

  @OptionGroup var selector: SelectorOptions
  @OptionGroup var options: GlobalOptions

  @Argument(help: "Worktree id/name/path or a pane/tab handle (auto-resolved). Defaults to the caller's pane.")
  var target: String?

  mutating func run() throws {
    try CLIExecution.run(
      command: WorkflowCommandPayload.commandName, output: options.outputMode, colorEnabled: options.colorEnabled
    ) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .workflow(WorkflowInput(action: .list, target: try selector.resolve(positionalTarget: target)))
      )
      try CLIRunner.execute(envelope)
    }
  }
}

struct WorkflowValidateCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "validate",
    abstract: "Parse and validate a workflow file locally; exits non-zero when it has errors."
  )

  enum Scope: String, ExpressibleByArgument, CaseIterable {
    case bundle
    case user
    case repo

    var value: WorkflowScope {
      switch self {
      case .bundle: .bundle
      case .user: .user
      case .repo: .repo
      }
    }
  }

  @Argument(help: "Path to a workflow YAML file.")
  var file: String

  @Option(
    name: .long,
    help: "Source the file belongs to (bundle, user, repo); inferred from its directory when omitted."
  )
  var scope: Scope?

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CLIExecution.run(
      command: WorkflowCommandPayload.commandName, output: options.outputMode, colorEnabled: options.colorEnabled
    ) {
      let payload = try WorkflowCommandExecutor.current().validate(path: file, scope: scope?.value)
      if payload.valid {
        try WorkflowCommandRunner.render(.validate(payload), options: options)
        return
      }
      // An invalid file is an error outcome whose details carry the full validate payload.
      let response = CommandResponse(
        ok: false,
        command: WorkflowCommandPayload.commandName,
        schemaVersion: WorkflowCommandPayload.schemaVersion,
        error: CommandError(
          code: CLIErrorCode.workflowInvalid,
          message: "\(payload.path) has \(payload.diagnostics.filter { $0.severity == .error }.count) error(s).",
          details: try RawJSON(encoding: payload)
        )
      )
      switch options.outputMode {
      case .json:
        OutputRenderer.render(response, mode: .json)
      case .text:
        print(OutputRenderer.workflowValidateText(payload))
      }
      throw ExitCode.failure
    }
  }
}

struct WorkflowSchemaCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "schema",
    abstract: "Print the JSON Schema of a workflow file (for authoring agents and editors)."
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CLIExecution.run(
      command: WorkflowCommandPayload.commandName, output: options.outputMode, colorEnabled: options.colorEnabled
    ) {
      try WorkflowCommandRunner.render(.schema(try WorkflowCommandExecutor.current().schema()), options: options)
    }
  }
}

enum WorkflowCommandRunner {
  static func render(_ payload: WorkflowCommandPayload, options: GlobalOptions) throws {
    let response = CommandResponse(
      ok: true,
      command: WorkflowCommandPayload.commandName,
      schemaVersion: WorkflowCommandPayload.schemaVersion,
      data: try RawJSON(encoding: payload)
    )
    OutputRenderer.render(response, mode: options.outputMode)
  }
}
