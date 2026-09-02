import SwiftUI

struct AgentIslandAttentionLayout: Equatable {
  static let cellHeight: CGFloat = 44
  static let spacing: CGFloat = 6
  static let maximumVisibleRows = 3

  let columnCount: Int
  let rowCount: Int
  let width: CGFloat
  let viewportHeight: CGFloat
  let isScrollable: Bool

  static func layout(entryCount: Int) -> Self {
    guard entryCount > 0 else {
      return Self(
        columnCount: 1,
        rowCount: 0,
        width: 286,
        viewportHeight: 0,
        isScrollable: false
      )
    }
    let columnCount = entryCount == 1 ? 1 : 2
    let rowCount = (entryCount + columnCount - 1) / columnCount
    let visibleRows = min(rowCount, maximumVisibleRows)
    let viewportHeight =
      CGFloat(visibleRows) * cellHeight
      + CGFloat(max(0, visibleRows - 1)) * spacing
    return Self(
      columnCount: columnCount,
      rowCount: rowCount,
      width: columnCount == 1 ? 286 : 380,
      viewportHeight: viewportHeight,
      isScrollable: rowCount > maximumVisibleRows
    )
  }
}

struct AgentIslandAttentionPresentation: Equatable {
  let agentName: String
  let statusLabel: String
  let repositoryName: String
  let subtitle: String

  static func presentation(
    for entry: ActiveAgentEntry,
    rowDisplay: ActiveAgentRowDisplay?,
    showTabTitles: Bool
  ) -> Self {
    let repositoryName = rowDisplay?.repositoryName ?? entry.worktreeName
    let branchName = rowDisplay?.branchName ?? entry.worktreeName
    return Self(
      agentName: entry.displayName,
      statusLabel: entry.displayState.label,
      repositoryName: repositoryName,
      subtitle: ActiveAgentRowPresentation.subtitle(
        for: entry,
        branchName: branchName,
        showTabTitles: showTabTitles
      )
    )
  }
}

struct AgentIslandAttentionCollection: View {
  let entries: [ActiveAgentEntry]
  let rowDisplays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay]
  let showTabTitles: Bool
  let onTap: (ActiveAgentEntry.ID) -> Void

  var body: some View {
    let layout = AgentIslandAttentionLayout.layout(entryCount: entries.count)
    ScrollView(.vertical) {
      LazyVGrid(columns: columns(for: layout), spacing: AgentIslandAttentionLayout.spacing) {
        ForEach(entries) { entry in
          attentionCell(entry)
        }
      }
    }
    .scrollIndicators(.never)
    .scrollDisabled(!layout.isScrollable)
    .frame(height: layout.viewportHeight)
    .padding(6)
    .frame(width: layout.width)
    .background(.black, in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(.white.opacity(0.12), lineWidth: 0.75)
    }
    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    .accessibilityIdentifier("agent-island-attention")
  }

  private func columns(for layout: AgentIslandAttentionLayout) -> [GridItem] {
    Array(
      repeating: GridItem(.flexible(), spacing: AgentIslandAttentionLayout.spacing),
      count: layout.columnCount
    )
  }

  private func attentionCell(_ entry: ActiveAgentEntry) -> some View {
    let presentation = AgentIslandAttentionPresentation.presentation(
      for: entry,
      rowDisplay: rowDisplays[entry.id],
      showTabTitles: showTabTitles
    )
    return Button {
      onTap(entry.id)
    } label: {
      HStack(spacing: 7) {
        AgentIslandRuntimeIcon(
          entry: entry,
          pointSize: 19
        )
        VStack(alignment: .leading, spacing: 1) {
          Text(presentation.agentName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(presentation.statusLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(entry.displayState.foregroundStyle)
            .lineLimit(1)
        }
        Spacer(minLength: 3)
        VStack(alignment: .trailing, spacing: 1) {
          Text(presentation.repositoryName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Text(presentation.subtitle)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        .multilineTextAlignment(.trailing)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity, minHeight: AgentIslandAttentionLayout.cellHeight)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(entry.displayState.foregroundStyle.opacity(0.34), lineWidth: 0.8)
    }
    .help("Open \(entry.displayName) in Prowl")
    .accessibilityLabel(
      "\(presentation.statusLabel), \(presentation.agentName), \(presentation.repositoryName), \(presentation.subtitle)"
    )
  }
}
