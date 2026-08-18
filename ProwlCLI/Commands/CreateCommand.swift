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
        command: .create(
          CreateInput(
            resource: .tab,
            selector: try selector.resolveWorktree(positionalTarget: worktree),
            path: normalizedPath()
          )
        )
      )
      try CLIRunner.execute(envelope)
    }
  }

  private func normalizedPath() -> String? {
    guard let path else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
      .path(percentEncoded: false)
      .trimmingTrailingSlash()
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
