import Foundation

public enum LifecyclePromptDelivery: String, Codable, Sendable, Equatable {
  case surfaceEnvironmentV1 = "surface_env_v1"
}

public struct LifecycleCommandLaunch: Codable, Sendable, Equatable {
  public let profileID: String
  public let profileName: String
  public let agent: String
  public let promptDelivery: LifecyclePromptDelivery?

  enum CodingKeys: String, CodingKey {
    case profileID = "profile_id"
    case profileName = "profile_name"
    case agent
    case promptDelivery = "prompt_delivery"
  }

  public init(
    profileID: String,
    profileName: String,
    agent: String,
    promptDelivery: LifecyclePromptDelivery? = nil
  ) {
    self.profileID = profileID
    self.profileName = profileName
    self.agent = agent
    self.promptDelivery = promptDelivery
  }
}

public struct LifecycleCommandPayload: Codable, Sendable, Equatable {
  public let resource: LifecycleResource
  public let anchor: TabTarget?
  public let direction: CreatePaneDirection?
  public let launch: LifecycleCommandLaunch?
  public let target: TabTarget

  public init(
    resource: LifecycleResource,
    anchor: TabTarget? = nil,
    direction: CreatePaneDirection? = nil,
    launch: LifecycleCommandLaunch? = nil,
    target: TabTarget
  ) {
    self.resource = resource
    self.anchor = anchor
    self.direction = direction
    self.launch = launch
    self.target = target
  }
}
