import Foundation

nonisolated struct UserGlobalSettings: Codable, Equatable, Sendable {
  var customCommands: [UserCustomCommand]

  static let `default` = UserGlobalSettings(customCommands: [])

  init(customCommands: [UserCustomCommand]) {
    self.customCommands = UserCustomCommand.normalizedCommands(customCommands)
  }

  func normalized() -> UserGlobalSettings {
    UserGlobalSettings(customCommands: customCommands)
  }
}
