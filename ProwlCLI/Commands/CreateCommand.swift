// ProwlCLI/Commands/CreateCommand.swift

import ArgumentParser
import Foundation
import ProwlCLIShared

struct CreateCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "create",
    abstract: "Create a terminal resource.",
    subcommands: [
      CreateTabCommand.self,
      CreatePaneCommand.self,
    ]
  )
}

struct CreateTabCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tab",
    abstract: "Create a new terminal tab."
  )

  @Argument(help: "Worktree id, name, or path.")
  var worktree: String?

  @OptionGroup var selector: LifecycleSelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Working directory for the new tab.")
  var path: String?

  mutating func run() throws {
    try CLIExecution.run(command: "create", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .create(try makeInput())
      )
      try CLIRunner.execute(envelope)
    }
  }

  func makeInput() throws -> CreateInput {
    CreateInput(
      resource: .tab,
      selector: try selector.resolveWorktree(positionalTarget: worktree),
      path: normalizedPath()
    )
  }

  private func normalizedPath() -> String? {
    guard let path else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
      .path(percentEncoded: false)
      .trimmingTrailingSlash()
  }
}

struct CreatePaneCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pane",
    abstract: "Create a split pane beside an existing pane."
  )

  enum Direction: String, ExpressibleByArgument {
    case right
    case left
    case up
    case down

    var value: CreatePaneDirection {
      switch self {
      case .right: .right
      case .left: .left
      case .up: .upward
      case .down: .down
      }
    }
  }

  @Argument(help: "Anchor pane UUID or short handle (for example, p3).")
  var anchor: String?

  @OptionGroup var selector: LifecycleSelectorOptions
  @OptionGroup var options: GlobalOptions

  @Option(name: .long, help: "Split direction: right, left, up, or down.")
  var direction: Direction

  mutating func run() throws {
    try CLIExecution.run(command: "create", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .create(try makeInput())
      )
      try CLIRunner.execute(envelope)
    }
  }

  func makeInput() throws -> CreateInput {
    CreateInput(
      resource: .pane,
      selector: try selector.resolvePane(positionalTarget: anchor),
      direction: direction.value
    )
  }
}

private extension String {
  func trimmingTrailingSlash() -> String {
    var value = self
    while value.count > 1, value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }
}
