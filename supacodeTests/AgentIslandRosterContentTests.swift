import CoreGraphics
import Testing

@testable import supacode

struct AgentIslandRosterContentTests {
  @Test func measuredContentUsesItsIntrinsicHeight() {
    let layout = AgentIslandRosterLayout.layout(
      entryCount: 4,
      measuredContentHeight: 196
    )

    #expect(layout.viewportHeight == 196)
    #expect(!layout.isScrollable)
  }

  @Test func tallContentStopsAtTheMaximumHeight() {
    let layout = AgentIslandRosterLayout.layout(
      entryCount: 12,
      measuredContentHeight: 588
    )

    #expect(layout.viewportHeight == AgentIslandRosterLayout.maximumViewportHeight)
    #expect(layout.isScrollable)
  }

  @Test func estimatedHeightAvoidsAnEmptyFirstLayout() {
    let layout = AgentIslandRosterLayout.layout(
      entryCount: 3,
      measuredContentHeight: nil
    )

    #expect(layout.viewportHeight == AgentIslandRosterLayout.estimatedRowHeight * 3)
    #expect(!layout.isScrollable)
  }
}
