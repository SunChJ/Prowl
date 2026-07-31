import Clocks
import Foundation
import Testing

@testable import supacode

@MainActor
struct DebouncerTests {
  @Test func actionFiresAfterInterval() async {
    let clock = TestClock()
    let debouncer = Debouncer(interval: .milliseconds(100), clock: clock)
    var fired = false

    debouncer.schedule { fired = true }
    await advance(clock, by: .milliseconds(99))
    #expect(!fired)

    await advance(clock, by: .milliseconds(1))
    #expect(fired)
  }

  @Test func reschedulingReplacesPendingActionAndRestartsInterval() async {
    let clock = TestClock()
    let debouncer = Debouncer(interval: .milliseconds(100), clock: clock)
    var firstFired = false
    var secondFired = false

    debouncer.schedule { firstFired = true }
    await advance(clock, by: .milliseconds(60))
    debouncer.schedule { secondFired = true }
    await advance(clock, by: .milliseconds(60))
    #expect(!firstFired)
    #expect(!secondFired)

    await advance(clock, by: .milliseconds(40))
    #expect(!firstFired)
    #expect(secondFired)
  }

  @Test func cancelledActionNeverFires() async {
    // The hand-rolled pattern this type replaces was easy to get wrong: a
    // `try? await sleep` swallows the cancellation error and the body runs
    // anyway, turning "cancel" into "fire immediately".
    let clock = TestClock()
    let debouncer = Debouncer(interval: .milliseconds(100), clock: clock)
    var fired = false

    debouncer.schedule { fired = true }
    await advance(clock, by: .milliseconds(50))
    debouncer.cancel()
    await advance(clock, by: .milliseconds(200))

    #expect(!fired)
  }

  @Test func isIdleTracksThePendingWindow() async {
    let clock = TestClock()
    let debouncer = Debouncer(interval: .milliseconds(100), clock: clock)
    #expect(debouncer.isIdle)

    debouncer.schedule {}
    #expect(!debouncer.isIdle)

    await advance(clock, by: .milliseconds(100))
    #expect(debouncer.isIdle)

    debouncer.schedule {}
    debouncer.cancel()
    #expect(debouncer.isIdle)
  }
}

@MainActor
struct KeyedDebouncerTests {
  @Test func keysDebounceIndependently() async {
    let clock = TestClock()
    let debouncer = KeyedDebouncer<String>(interval: .milliseconds(100), clock: clock)
    var fired: [String] = []

    debouncer.schedule("a") { fired.append("a") }
    await advance(clock, by: .milliseconds(50))
    debouncer.schedule("b") { fired.append("b") }
    // Rescheduling "a" must not affect "b"'s window.
    debouncer.schedule("a") { fired.append("a2") }

    await advance(clock, by: .milliseconds(100))
    #expect(fired.sorted() == ["a2", "b"])
  }

  @Test func perCallIntervalOverridesDefault() async {
    let clock = TestClock()
    let debouncer = KeyedDebouncer<String>(interval: .seconds(10), clock: clock)
    var fired = false

    debouncer.schedule("a", after: .milliseconds(100)) { fired = true }
    await advance(clock, by: .milliseconds(100))

    #expect(fired)
  }

  @Test func cancelOnlyAffectsTheGivenKey() async {
    let clock = TestClock()
    let debouncer = KeyedDebouncer<String>(interval: .milliseconds(100), clock: clock)
    var fired: [String] = []

    debouncer.schedule("a") { fired.append("a") }
    debouncer.schedule("b") { fired.append("b") }
    debouncer.cancel("a")
    await advance(clock, by: .milliseconds(100))

    #expect(fired == ["b"])
  }

  @Test func cancelAllSupportsSelectivePredicate() async {
    let clock = TestClock()
    let debouncer = KeyedDebouncer<String>(interval: .milliseconds(100), clock: clock)
    var fired: [String] = []

    debouncer.schedule("keep") { fired.append("keep") }
    debouncer.schedule("drop-1") { fired.append("drop-1") }
    debouncer.schedule("drop-2") { fired.append("drop-2") }
    debouncer.cancelAll { $0.hasPrefix("drop") }
    await advance(clock, by: .milliseconds(100))

    #expect(fired == ["keep"])
  }

  @Test func cancelAllCancelsEverything() async {
    let clock = TestClock()
    let debouncer = KeyedDebouncer<String>(interval: .milliseconds(100), clock: clock)
    var fired: [String] = []

    debouncer.schedule("a") { fired.append("a") }
    debouncer.schedule("b") { fired.append("b") }
    debouncer.cancelAll()
    await advance(clock, by: .milliseconds(200))

    #expect(fired.isEmpty)
  }
}

@MainActor
private func advance(_ clock: TestClock<Duration>, by duration: Duration) async {
  await clock.advance(by: duration)
  // Deadlines are anchored at `schedule` time, so a debounce task that starts
  // after the advance still resumes immediately — but it needs a few executor
  // hops to run its continuation on a loaded machine. A short yield burst
  // keeps that deterministic without real-time sleeping.
  for _ in 0..<10 {
    await Task.yield()
  }
}
