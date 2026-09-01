import ComposableArchitecture
import SwiftUI

struct ActiveAgentRow: View {
  let entry: ActiveAgentEntry
  let repositoryName: String
  let subtitle: String
  let repositoryColor: RepositoryColorChoice?
  let isDimmed: Bool
  var body: some View {
    HStack(spacing: 8) {
      agentIcon
      VStack(alignment: .leading, spacing: 2) {
        title
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 8)
      statusPill
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .contentShape(.rect)
    .opacity(isDimmed ? 0.7 : 1)
  }

  private var title: some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
      Text(entry.displayName)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
      Text("·")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
      Text(repositoryName)
        .font(.callout.weight(.medium))
        .foregroundStyle(repositoryColor?.color ?? .secondary)
    }
    .lineLimit(1)
  }

  private var agentIcon: some View {
    AgentStatusIcon(entry: entry, pointSize: 18, indicatorSize: 8)
      .frame(width: 20, height: 20)
  }

  private var statusPill: some View {
    Label(entry.displayState.label, systemImage: entry.displayState.statusSymbolName)
      .font(.caption2.weight(.semibold))
      .lineLimit(1)
      .labelStyle(.titleAndIcon)
      .foregroundStyle(entry.displayState.foregroundStyle)
  }
}
