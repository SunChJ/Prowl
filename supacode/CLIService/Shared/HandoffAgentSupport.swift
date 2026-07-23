import Foundation

public enum HandoffAgentSupport {
  public static let supportedAgents = [
    "pi",
    "claude",
    "codex",
    "gemini",
    "cursor-agent",
    "cline",
    "opencode",
    "copilot",
    "kimi",
    "droid",
    "amp",
    "qodercli",
    "qwen",
    "grok",
  ]

  public static let launchableAgents = ["claude", "codex"]

  public static var supportedAgentsDescription: String {
    supportedAgents.joined(separator: ", ")
  }

  public static var launchableAgentsDescription: String {
    launchableAgents.joined(separator: ", ")
  }

  public static func canLaunch(_ agent: String) -> Bool {
    launchableAgents.contains(agent)
  }

  public static func normalize(_ agent: String) -> String? {
    let normalized = agent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard supportedAgents.contains(normalized) else { return nil }
    return normalized
  }
}
