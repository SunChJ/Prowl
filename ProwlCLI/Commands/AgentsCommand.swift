// ProwlCLI/Commands/AgentsCommand.swift

import ArgumentParser
import ProwlCLIShared

struct AgentsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "agents",
    abstract: "List detected agent panes.",
    subcommands: [AgentsReadCommand.self]
  )

  @OptionGroup var options: GlobalOptions

  mutating func run() throws {
    try CLIExecution.run(command: "agents", output: options.outputMode, colorEnabled: options.colorEnabled) {
      let envelope = CommandEnvelope(
        output: options.outputMode,
        command: .agents(AgentsInput())
      )
      try CLIRunner.execute(envelope)
    }
  }
}
