import Foundation
import Testing

@testable import supacode

/// `TerminalTabManager.tabs` is observed as a whole, so one tab's title write
/// rebuilds the entire tab bar. Agent TUIs animate a spinner glyph into the
/// title at roughly 10 Hz, so live title writes are spaced out; these tests pin
/// both the spacing and the trailing flush that keeps a settled title from
/// being stranded.
@MainActor
struct TerminalTabTitleCoalescingTests {
  private let start = Date(timeIntervalSince1970: 1_000)

  private func makeManager() -> (TerminalTabManager, TerminalTabID) {
    let manager = TerminalTabManager()
    let id = manager.createTab(title: "initial", icon: nil)
    return (manager, id)
  }

  private func title(of manager: TerminalTabManager, _ id: TerminalTabID) -> String? {
    manager.tabs.first(where: { $0.id == id })?.title
  }

  @Test func theFirstTitleAfterAQuietPeriodIsWrittenImmediately() {
    let (manager, id) = makeManager()

    #expect(manager.updateTitle(id, title: "building", now: start))
    #expect(title(of: manager, id) == "building")
  }

  @Test func framesArrivingInsideTheIntervalDoNotReachTheTabs() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "⠋ working", now: start)

    #expect(manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.1)) == false)
    #expect(manager.updateTitle(id, title: "⠹ working", now: start.addingTimeInterval(0.2)) == false)

    #expect(
      title(of: manager, id) == "⠋ working",
      "Animation frames must not mutate the observed array"
    )
  }

  @Test func aTitleArrivingAfterTheIntervalIsWrittenAgain() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "⠋ working", now: start)
    _ = manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.5))

    #expect(manager.updateTitle(id, title: "⠸ working", now: start.addingTimeInterval(1.1)))
    #expect(title(of: manager, id) == "⠸ working")
  }

  /// Only the newest held-back title survives, so a burst never queues up.
  @Test func flushLandsTheMostRecentSuppressedTitle() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "⠋ working", now: start)
    _ = manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.2))
    _ = manager.updateTitle(id, title: "⠸ working", now: start.addingTimeInterval(0.4))

    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(1.5)) == [id])
    #expect(title(of: manager, id) == "⠸ working")
  }

  @Test func flushDoesNothingBeforeTheIntervalElapses() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "⠋ working", now: start)
    _ = manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.2))

    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(0.5)).isEmpty)
    #expect(title(of: manager, id) == "⠋ working")
  }

  @Test func flushIsANoOpWhenNothingWasSuppressed() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "done", now: start)

    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(5)).isEmpty)
    #expect(title(of: manager, id) == "done")
  }

  /// A suppressed frame must not resurface after a later title has been written,
  /// or the tab would flick back to a stale animation frame.
  @Test func aSuppressedTitleIsDiscardedOnceANewerOneIsWritten() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "⠋ working", now: start)
    _ = manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.2))
    _ = manager.updateTitle(id, title: "finished", now: start.addingTimeInterval(1.1))

    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(9)).isEmpty)
    #expect(title(of: manager, id) == "finished")
  }

  @Test func coalescingIsPerTabNotGlobal() {
    let manager = TerminalTabManager()
    let first = manager.createTab(title: "first", icon: nil)
    let second = manager.createTab(title: "second", icon: nil)

    #expect(manager.updateTitle(first, title: "⠋ one", now: start))
    // The second tab has its own history, so its first write is not held back.
    #expect(manager.updateTitle(second, title: "⠋ two", now: start.addingTimeInterval(0.1)))

    #expect(title(of: manager, first) == "⠋ one")
    #expect(title(of: manager, second) == "⠋ two")
  }

  @Test func aLockedTitleIsNeverWrittenOrHeld() {
    let manager = TerminalTabManager()
    let id = manager.createTab(title: "pinned", icon: nil, isTitleLocked: true)

    #expect(manager.updateTitle(id, title: "⠋ working", now: start) == false)
    #expect(manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.2)) == false)
    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(5)).isEmpty)
    #expect(title(of: manager, id) == "pinned")
  }

  /// A custom title masks the live one, so the visible title never moves — the
  /// live value still updates underneath so clearing the custom title reveals it.
  @Test func aCustomTitleMasksTheFlushedLiveTitle() {
    let (manager, id) = makeManager()
    _ = manager.setCustomTitle(id, title: "my tab")
    _ = manager.updateTitle(id, title: "⠋ working", now: start)
    _ = manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.2))

    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(1.5)).isEmpty)
    #expect(title(of: manager, id) == "⠙ working")
    #expect(manager.tabs.first(where: { $0.id == id })?.displayTitle == "my tab")
  }

  @Test func closingATabDropsItsCoalescingState() {
    let (manager, id) = makeManager()
    _ = manager.updateTitle(id, title: "⠋ working", now: start)
    _ = manager.updateTitle(id, title: "⠙ working", now: start.addingTimeInterval(0.2))
    manager.closeTab(id)

    #expect(manager.flushPendingTitles(now: start.addingTimeInterval(5)).isEmpty)
    #expect(manager.tabs.isEmpty)
  }
}
