import Foundation
import Testing

@testable import supacode

struct HeixiuWorkingIndicatorTests {
  @Test func cycleStartsAndEndsWithAttachedTail() {
    let duration = HeixiuWorkingIndicator.cycleDuration

    #expect(HeixiuWorkingIndicator.motion(at: date(phase: 0)) == .attached)
    #expect(HeixiuWorkingIndicator.motion(at: date(phase: 0.96)).tailOpacity == 1)
    #expect(HeixiuWorkingIndicator.motion(at: date(phase: 0.96)).ballOpacity == 0)
    #expect(HeixiuWorkingIndicator.motion(at: date(phase: 1)).tailOpacity == 1)
    #expect(duration > 0)
  }

  @Test func tailCondensesIntoASeparatedBallAndReconnects() {
    let detaching = HeixiuWorkingIndicator.motion(at: date(phase: 0.5))
    let separated = HeixiuWorkingIndicator.motion(at: date(phase: 0.68))
    let reconnecting = HeixiuWorkingIndicator.motion(at: date(phase: 0.86))

    #expect(detaching.tailOpacity > 0)
    #expect(detaching.tailOpacity < 1)
    #expect(detaching.ballOpacity > 0)
    #expect(detaching.ballOpacity < 1)

    #expect(separated.tailOpacity == 0)
    #expect(separated.ballOpacity == 1)
    #expect(separated.ballScale == 1)
    #expect(separated.ballOffset.height < 0)

    #expect(reconnecting.tailOpacity > 0)
    #expect(reconnecting.tailOpacity < 1)
    #expect(reconnecting.ballOpacity > 0)
    #expect(reconnecting.ballOpacity < 1)
  }

  @Test func negativeReferenceTimesStillResolveWithinTheCycle() {
    let motion = HeixiuWorkingIndicator.motion(
      at: Date(timeIntervalSinceReferenceDate: -HeixiuWorkingIndicator.cycleDuration)
    )

    #expect(motion == .attached)
  }

  private func date(phase: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: HeixiuWorkingIndicator.cycleDuration * phase)
  }
}
