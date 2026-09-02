import Foundation
import Testing

@testable import supacode

struct WorkflowBindModeOverrideTests {
  @Test func overrideRoundTripsThroughCoding() throws {
    var settings = UserGlobalSettings(customCommands: [])
    settings.setWorkflowBindMode(.auto, for: "bundle/prowl.adversarial-review")
    settings.setWorkflowBindMode(.ask, for: "user/my-review")

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(UserGlobalSettings.self, from: data)

    #expect(decoded.workflowBindMode(for: "bundle/prowl.adversarial-review") == .auto)
    #expect(decoded.workflowBindMode(for: "user/my-review") == .ask)
    #expect(decoded.workflowBindMode(for: "repo:abc/other") == nil)
  }

  @Test func settingNilClearsTheOverride() {
    var settings = UserGlobalSettings(customCommands: [])
    settings.setWorkflowBindMode(.auto, for: "user/my-review")
    settings.setWorkflowBindMode(nil, for: "user/my-review")

    #expect(settings.workflowBindMode(for: "user/my-review") == nil)
    #expect(settings.workflowBindModeOverrides.isEmpty)
  }

  @Test func lastWriteWinsPerKeyAndOrderIsStable() {
    let overrides = [
      WorkflowBindModeOverride(workflowKey: "user/b", mode: .ask),
      WorkflowBindModeOverride(workflowKey: "user/a", mode: .ask),
      WorkflowBindModeOverride(workflowKey: "user/b", mode: .auto),
    ]

    let normalized = WorkflowBindModeOverride.normalized(overrides)

    #expect(
      normalized == [
        WorkflowBindModeOverride(workflowKey: "user/a", mode: .ask),
        WorkflowBindModeOverride(workflowKey: "user/b", mode: .auto),
      ])
  }

  @Test func decodingWithoutTheKeyDefaultsToEmpty() throws {
    let json = #"{"customCommands":[]}"#
    let decoded = try JSONDecoder().decode(UserGlobalSettings.self, from: Data(json.utf8))
    #expect(decoded.workflowBindModeOverrides.isEmpty)
  }

  @Test func normalizedForwardsOverrides() {
    var settings = UserGlobalSettings(customCommands: [])
    settings.setWorkflowBindMode(.auto, for: "user/my-review")
    #expect(settings.normalized().workflowBindMode(for: "user/my-review") == .auto)
  }
}
