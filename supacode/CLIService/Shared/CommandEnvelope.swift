// ProwlShared/CommandEnvelope.swift
// The handoff contract between CLI parser and app command service.

import Foundation

public struct CommandEnvelope: Codable, Sendable {
  public let output: OutputMode
  public let command: Command

  public init(output: OutputMode, command: Command) {
    self.output = output
    self.command = command
  }
}

public enum Command: Codable, Sendable {
  case open(OpenInput)
  case list(ListInput)
  case agents(AgentsInput)
  case agentsRead(AgentReadInput)
  case profiles(ProfilesInput)
  case focus(FocusInput)
  case send(SendInput)
  case key(KeyInput)
  case read(ReadInput)
  case create(CreateInput)
  case close(CloseInput)
  case tab(TabInput)
  case pane(PaneInput)
  case handoff(HandoffInput)

  public var name: String {
    switch self {
    case .open: "open"
    case .list: "list"
    case .agents: "agents"
    case .agentsRead: "agents.read"
    case .profiles: "profiles"
    case .focus: "focus"
    case .send: "send"
    case .key: "key"
    case .read: "read"
    case .create: "create"
    case .close: "close"
    case .tab: "tab"
    case .pane: "pane"
    case .handoff: "handoff"
    }
  }
}
