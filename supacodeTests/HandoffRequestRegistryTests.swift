import Foundation
import Testing

@testable import supacode

@MainActor
struct HandoffRequestRegistryTests {
  @Test func requestCanBeClaimedOnlyOnce() {
    let registry = HandoffRequestRegistry()
    let requestID = UUID()

    registry.register(requestID)

    #expect(registry.claim(requestID))
    #expect(!registry.claim(requestID))
  }

  @Test func fallbackSupersedesPendingRequest() {
    let registry = HandoffRequestRegistry()
    let requestID = UUID()

    registry.register(requestID)

    #expect(registry.supersede(requestID))
    #expect(!registry.claim(requestID))
  }

  @Test func fallbackCannotSupersedeClaimedRequest() {
    let registry = HandoffRequestRegistry()
    let requestID = UUID()

    registry.register(requestID)
    #expect(registry.claim(requestID))

    #expect(!registry.supersede(requestID))
  }
}
