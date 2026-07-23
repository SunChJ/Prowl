// supacode/CLIService/CLICommandRouter.swift
// Routes incoming command envelopes to the appropriate handler.

import Foundation

@MainActor
final class CLICommandRouter {
  private let openHandler: any CommandHandler
  private let listHandler: any CommandHandler
  private let agentsHandler: any CommandHandler
  private let focusHandler: any CommandHandler
  private let sendHandler: any CommandHandler
  private let keyHandler: any CommandHandler
  private let readHandler: any CommandHandler
  private let tabHandler: any CommandHandler
  private let paneHandler: any CommandHandler
  private let handoffHandler: any CommandHandler

  init(
    openHandler: any CommandHandler = StubCommandHandler(command: "open"),
    listHandler: any CommandHandler = StubCommandHandler(command: "list"),
    agentsHandler: any CommandHandler = StubCommandHandler(command: "agents"),
    focusHandler: any CommandHandler = StubCommandHandler(command: "focus"),
    sendHandler: any CommandHandler = StubCommandHandler(command: "send"),
    keyHandler: any CommandHandler = StubCommandHandler(command: "key"),
    readHandler: any CommandHandler = StubCommandHandler(command: "read"),
    tabHandler: any CommandHandler = StubCommandHandler(command: "tab"),
    paneHandler: any CommandHandler = StubCommandHandler(command: "pane"),
    handoffHandler: any CommandHandler = StubCommandHandler(command: "handoff")
  ) {
    self.openHandler = openHandler
    self.listHandler = listHandler
    self.agentsHandler = agentsHandler
    self.focusHandler = focusHandler
    self.sendHandler = sendHandler
    self.keyHandler = keyHandler
    self.readHandler = readHandler
    self.tabHandler = tabHandler
    self.paneHandler = paneHandler
    self.handoffHandler = handoffHandler
  }

  func route(
    _ envelope: CommandEnvelope,
    context: CLICommandContext = CLICommandContext()
  ) async -> CommandResponse {
    let handler: any CommandHandler
    switch envelope.command {
    case .open: handler = openHandler
    case .list: handler = listHandler
    case .agents: handler = agentsHandler
    case .focus: handler = focusHandler
    case .send: handler = sendHandler
    case .key: handler = keyHandler
    case .read: handler = readHandler
    case .tab: handler = tabHandler
    case .pane: handler = paneHandler
    case .handoff: handler = handoffHandler
    }
    return await handler.handle(envelope: envelope, context: context)
  }
}

// MARK: - Stub handler (placeholder until real handlers are implemented)

struct StubCommandHandler: CommandHandler {
  let command: String

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    CommandResponse(
      ok: false,
      command: command,
      schemaVersion: "prowl.cli.\(command).v1",
      error: CommandError(
        code: "NOT_IMPLEMENTED",
        message: "Command '\(command)' is not yet implemented."
      )
    )
  }
}
