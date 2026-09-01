import Foundation
import Testing

@testable import supacode

struct AgentIslandAttentionCollectionTests {
  @Test func singleEntryUsesCompactSingleColumnLayout() {
    let layout = AgentIslandAttentionLayout.layout(entryCount: 1)

    #expect(layout.columnCount == 1)
    #expect(layout.rowCount == 1)
    #expect(layout.width == 286)
    #expect(layout.viewportHeight == 44)
    #expect(!layout.isScrollable)
  }

  @Test func multipleEntriesUseTwoColumnCollection() {
    let layout = AgentIslandAttentionLayout.layout(entryCount: 5)

    #expect(layout.columnCount == 2)
    #expect(layout.rowCount == 3)
    #expect(layout.width == 380)
    #expect(layout.viewportHeight == 144)
    #expect(!layout.isScrollable)
  }

  @Test func collectionScrollsBeyondThreeRows() {
    let layout = AgentIslandAttentionLayout.layout(entryCount: 7)

    #expect(layout.columnCount == 2)
    #expect(layout.rowCount == 4)
    #expect(layout.width == 380)
    #expect(layout.viewportHeight == 144)
    #expect(layout.isScrollable)
  }

  @Test func blockedPresentationUsesSharedLabelAndResolvedWorktree() {
    let presentation = AgentIslandAttentionPresentation.presentation(
      for: entry(state: .blocked, paneTitle: "Approval"),
      rowDisplay: ActiveAgentRowDisplay(
        repositoryName: "Prowl",
        branchName: "feature/island",
        color: nil,
        directory: nil
      ),
      showTabTitles: false
    )

    #expect(presentation.statusLabel == "Blocked")
    #expect(presentation.repositoryName == "Prowl")
    #expect(presentation.subtitle == "feature/island")
  }

  @Test func donePresentationMatchesThePanelTabTitleSetting() {
    let presentation = AgentIslandAttentionPresentation.presentation(
      for: entry(state: .done, paneTitle: "Implementation"),
      rowDisplay: ActiveAgentRowDisplay(
        repositoryName: "Prowl",
        branchName: "feature/island",
        color: nil,
        directory: nil
      ),
      showTabTitles: true
    )

    #expect(presentation.statusLabel == "Done")
    #expect(presentation.repositoryName == "Prowl")
    #expect(presentation.subtitle == "Implementation")
  }

  private func entry(state: AgentDisplayState, paneTitle: String) -> ActiveAgentEntry {
    let id = UUID()
    return ActiveAgentEntry(
      id: id,
      worktreeID: "/repo/wt",
      worktreeName: "wt",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      paneTitle: paneTitle,
      surfaceID: id,
      paneIndex: 1,
      iconLookupToken: DetectedAgent.codex.iconLookupToken,
      agent: .codex,
      rawState: state == .blocked ? .blocked : .idle,
      displayState: state,
      lastChangedAt: .now
    )
  }
}
