import Foundation

public struct LifecycleCommandLaunch: Codable, Sendable, Equatable {
  public let profileID: String
  public let profileName: String
  public let agent: String

  enum CodingKeys: String, CodingKey {
    case profileID = "profile_id"
    case profileName = "profile_name"
    case agent
  }

  public init(profileID: String, profileName: String, agent: String) {
    self.profileID = profileID
    self.profileName = profileName
    self.agent = agent
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
