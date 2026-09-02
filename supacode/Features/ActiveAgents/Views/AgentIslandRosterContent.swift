import ComposableArchitecture
import SwiftUI

struct AgentIslandRosterLayout: Equatable {
  static let estimatedRowHeight: CGFloat = 50
  static let maximumViewportHeight: CGFloat = 360

  let viewportHeight: CGFloat
  let isScrollable: Bool

  static func layout(
    entryCount: Int,
    measuredContentHeight: CGFloat?
  ) -> Self {
    let estimatedContentHeight = CGFloat(entryCount) * estimatedRowHeight
    let contentHeight = max(0, measuredContentHeight ?? estimatedContentHeight)
    return Self(
      viewportHeight: min(contentHeight, maximumViewportHeight),
      isScrollable: contentHeight > maximumViewportHeight
    )
  }
}

/// Agent Island's expanded roster, composed from the original Active Agents row.
struct AgentIslandRosterContent: View {
  @Bindable var store: StoreOf<ActiveAgentsFeature>
  let rowDisplays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay]
  let workflowBadges: [UUID: String]
  let selectedSurfaceID: UUID?
  let showTabTitles: Bool
  let entryAction: (ActiveAgentEntry.ID) -> ActiveAgentsFeature.Action
  @State private var measuredContentHeight: CGFloat?

  var body: some View {
    let layout = AgentIslandRosterLayout.layout(
      entryCount: store.entries.count,
      measuredContentHeight: measuredContentHeight
    )
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(store.entries) { entry in
          Button {
            store.send(entryAction(entry.id))
          } label: {
            ActiveAgentRow(
              entry: entry,
              repositoryName: repositoryName(for: entry),
              subtitle: subtitle(for: entry),
              repositoryColor: repositoryColor(for: entry),
              isDimmed: isDimmed(entry)
            )
          }
          .buttonStyle(.plain)
          .help(helpText(for: entry))
          .contextMenu {
            ActiveAgentRowContextMenu(
              entry: entry,
              directory: rowDisplays[entry.id]?.directory,
              send: { store.send($0) }
            )
          }
        }
      }
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.height
      } action: { height in
        measuredContentHeight = height
      }
    }
    .scrollIndicators(.never)
    .scrollDisabled(!layout.isScrollable)
    .frame(height: layout.viewportHeight)
    .onChange(of: store.entries.count) { _, _ in
      measuredContentHeight = nil
    }
  }

  private func repositoryName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.repositoryName ?? entry.worktreeName
  }

  private func branchName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.branchName ?? entry.worktreeName
  }

  private func subtitle(for entry: ActiveAgentEntry) -> String {
    ActiveAgentRowPresentation.subtitle(
      for: entry,
      branchName: branchName(for: entry),
      showTabTitles: showTabTitles,
      workflowBadge: workflowBadges[entry.surfaceID]
    )
  }

  private func repositoryColor(for entry: ActiveAgentEntry) -> RepositoryColorChoice? {
    rowDisplays[entry.id]?.color
  }

  private func isDimmed(_ entry: ActiveAgentEntry) -> Bool {
    selectedSurfaceID.map { entry.surfaceID != $0 } ?? false
  }

  private func helpText(for entry: ActiveAgentEntry) -> String {
    ActiveAgentRowPresentation.helpText(
      for: entry,
      branchName: branchName(for: entry),
      showTabTitles: showTabTitles
    )
  }
}
