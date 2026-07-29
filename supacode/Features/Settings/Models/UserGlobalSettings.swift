import Foundation

nonisolated struct UserGlobalSettings: Codable, Equatable, Sendable {
  var customCommands: [UserCustomCommand]
  var agentProfiles: [AgentProfile]
  /// One-shot seeding marker for agent profiles (docs-ai 053): seeded profiles
  /// the user deletes must never respawn.
  var didSeedAgentProfiles: Bool

  static let `default` = UserGlobalSettings(customCommands: [])

  private enum CodingKeys: String, CodingKey {
    case customCommands
    case agentProfiles
    case didSeedAgentProfiles
  }

  init(
    customCommands: [UserCustomCommand],
    agentProfiles: [AgentProfile] = [],
    didSeedAgentProfiles: Bool = false
  ) {
    self.customCommands = UserCustomCommand.normalizedCommands(customCommands)
    self.agentProfiles = AgentProfile.normalizedProfiles(agentProfiles)
    self.didSeedAgentProfiles = didSeedAgentProfiles
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let commands = try container.decodeIfPresent([UserCustomCommand].self, forKey: .customCommands) ?? []
    customCommands = UserCustomCommand.normalizedCommands(commands)
    let profiles = try container.decodeIfPresent([AgentProfile].self, forKey: .agentProfiles) ?? []
    agentProfiles = AgentProfile.normalizedProfiles(profiles)
    didSeedAgentProfiles = try container.decodeIfPresent(Bool.self, forKey: .didSeedAgentProfiles) ?? false
  }

  func normalized() -> UserGlobalSettings {
    UserGlobalSettings(
      customCommands: customCommands,
      agentProfiles: agentProfiles,
      didSeedAgentProfiles: didSeedAgentProfiles
    )
  }
}
