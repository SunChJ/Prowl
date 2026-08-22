import Foundation

public struct LifecycleCommandPayload: Codable, Sendable, Equatable {
  public let resource: LifecycleResource
  public let anchor: TabTarget?
  public let direction: CreatePaneDirection?
  public let target: TabTarget

  public init(
    resource: LifecycleResource,
    anchor: TabTarget? = nil,
    direction: CreatePaneDirection? = nil,
    target: TabTarget
  ) {
    self.resource = resource
    self.anchor = anchor
    self.direction = direction
    self.target = target
  }
}
