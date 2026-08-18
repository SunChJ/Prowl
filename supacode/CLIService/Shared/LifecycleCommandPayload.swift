import Foundation

public struct LifecycleCommandPayload: Codable, Sendable, Equatable {
  public let resource: LifecycleResource
  public let target: TabTarget

  public init(resource: LifecycleResource, target: TabTarget) {
    self.resource = resource
    self.target = target
  }
}
