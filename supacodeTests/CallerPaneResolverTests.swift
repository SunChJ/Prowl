import Foundation
import Testing

@testable import supacode

struct CallerPaneResolverTests {
  @Test func resolvesDirectAndNestedCallerAncestry() {
    let pane = CallerPane(worktreeID: "wt", surfaceID: UUID())
    let parents: [pid_t: pid_t] = [400: 300, 300: 200, 200: 100]

    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 100,
        paneByShellPID: [100: pane],
        parentProcessID: { parents[$0] }
      ) == pane
    )
    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 400,
        paneByShellPID: [100: pane],
        parentProcessID: { parents[$0] }
      ) == pane
    )
  }

  @Test func unresolvedAndCyclicAncestryNeverGuess() {
    let focusedButUnrelated = CallerPane(worktreeID: "focused", surfaceID: UUID())

    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 400,
        paneByShellPID: [100: focusedButUnrelated],
        parentProcessID: { _ in nil }
      ) == nil
    )
    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 400,
        paneByShellPID: [100: focusedButUnrelated],
        parentProcessID: { $0 }
      ) == nil
    )
  }

  @Test func ancestryWalkIsBounded() {
    let pane = CallerPane(worktreeID: "wt", surfaceID: UUID())

    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 100,
        paneByShellPID: [67: pane],
        parentProcessID: { $0 - 1 }
      ) == nil
    )
    #expect(
      CallerPaneResolver.pane(
        forCallerProcess: 100,
        paneByShellPID: [69: pane],
        parentProcessID: { $0 - 1 }
      ) == pane
    )
  }
}
