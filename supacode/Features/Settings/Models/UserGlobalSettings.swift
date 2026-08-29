import Foundation

nonisolated struct UserGlobalSettings: Codable, Equatable, Sendable {
  var customCommands: [UserCustomCommand]
  var agentProfiles: [AgentProfile]
  /// One-shot seeding marker for agent profiles (docs-ai 053): seeded profiles
  /// the user deletes must never respawn.
  var didSeedAgentProfiles: Bool
  /// `<scope>/<id>` keys of workflow definitions switched off (docs-ai 063 B1; Settings UI in D1).
  var disabledWorkflowIDs: [String]

  static let `default` = UserGlobalSettings(customCommands: [])

  private enum CodingKeys: String, CodingKey {
    case customCommands
    case agentProfiles
    case didSeedAgentProfiles
    case disabledWorkflowIDs
  }

  init(
    customCommands: [UserCustomCommand],
    agentProfiles: [AgentProfile] = [],
    didSeedAgentProfiles: Bool = false,
    disabledWorkflowIDs: [String] = []
  ) {
    self.customCommands = UserCustomCommand.normalizedCommands(customCommands)
    self.agentProfiles = AgentProfile.normalizedProfiles(agentProfiles)
    self.didSeedAgentProfiles = didSeedAgentProfiles
    self.disabledWorkflowIDs = Self.normalizedWorkflowIDs(disabledWorkflowIDs)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let commands = try container.decodeIfPresent([UserCustomCommand].self, forKey: .customCommands) ?? []
    customCommands = UserCustomCommand.normalizedCommands(commands)
    let profiles = try container.decodeIfPresent([AgentProfile].self, forKey: .agentProfiles) ?? []
    agentProfiles = AgentProfile.normalizedProfiles(profiles)
    didSeedAgentProfiles = try container.decodeIfPresent(Bool.self, forKey: .didSeedAgentProfiles) ?? false
    let disabled = try container.decodeIfPresent([String].self, forKey: .disabledWorkflowIDs) ?? []
    disabledWorkflowIDs = Self.normalizedWorkflowIDs(disabled)
  }

  func normalized() -> UserGlobalSettings {
    UserGlobalSettings(
      customCommands: customCommands,
      agentProfiles: agentProfiles,
      didSeedAgentProfiles: didSeedAgentProfiles,
      disabledWorkflowIDs: disabledWorkflowIDs
    )
  }

  /// Stable order, no duplicates: the set semantics of a persisted list.
  static func normalizedWorkflowIDs(_ ids: [String]) -> [String] {
    Array(Set(ids)).sorted()
  }
}
