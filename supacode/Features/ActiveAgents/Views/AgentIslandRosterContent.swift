import AppKit
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
            contextMenu(for: entry)
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

  @ViewBuilder
  private func contextMenu(for entry: ActiveAgentEntry) -> some View {
    Button("Hand Off…") {
      store.send(.handOffTapped(entry.id))
    }
    .help("Save this agent's progress and hand the task off to another agent")
    Button("Mark as Read") {
      store.send(.markAsReadTapped(entry.id))
    }
    .help("Clear this agent's unread notifications without switching to it")
    if let directory = rowDisplays[entry.id]?.directory {
      Divider()
      Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(directory.path, forType: .string)
      }
      .help("Copy the agent's working directory path")
      Button("Reveal in Finder") {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
      }
      .help("Reveal the agent's working directory in Finder")
    }
    if let transcriptPath = entry.session?.transcriptPath {
      Divider()
      Button("Copy Session Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptPath.path, forType: .string)
      }
      .help("Copy the on-disk path of this agent's session log")
      Button("Reveal Session in Finder") {
        NSWorkspace.shared.selectFile(
          transcriptPath.path,
          inFileViewerRootedAtPath: transcriptPath.deletingLastPathComponent().path
        )
      }
      .help("Select this agent's session log in Finder")
    }
  }

  private func repositoryName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.repositoryName ?? entry.worktreeName
  }

  private func branchName(for entry: ActiveAgentEntry) -> String {
    rowDisplays[entry.id]?.branchName ?? entry.worktreeName
  }

  private func subtitle(for entry: ActiveAgentEntry) -> String {
    Self.subtitle(
      for: entry,
      branchName: branchName(for: entry),
      showTabTitles: showTabTitles
    )
  }

  private func repositoryColor(for entry: ActiveAgentEntry) -> RepositoryColorChoice? {
    rowDisplays[entry.id]?.color
  }

  private func isDimmed(_ entry: ActiveAgentEntry) -> Bool {
    selectedSurfaceID.map { entry.surfaceID != $0 } ?? false
  }

  private func helpText(for entry: ActiveAgentEntry) -> String {
    Self.helpText(
      for: entry,
      branchName: branchName(for: entry),
      showTabTitles: showTabTitles
    )
  }

  static func subtitle(
    for entry: ActiveAgentEntry,
    branchName: String,
    showTabTitles: Bool
  ) -> String {
    showTabTitles ? paneTitle(for: entry) : branchName
  }

  static func helpText(
    for entry: ActiveAgentEntry,
    branchName: String,
    showTabTitles: Bool
  ) -> String {
    showTabTitles ? branchName : paneTitle(for: entry)
  }

  static func paneTitle(for entry: ActiveAgentEntry) -> String {
    let trimmed = entry.paneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled tab" : trimmed
  }
}
