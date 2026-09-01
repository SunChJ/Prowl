import SwiftUI

/// A compact, island-owned projection of the real Active Agents roster.
struct AgentIslandIconCluster: View {
  struct Projection: Equatable {
    let entries: [ActiveAgentEntry]
    let overflowCount: Int
  }

  private static let maximumVisibleIcons = 3

  let projection: Projection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(entries: [ActiveAgentEntry]) {
    projection = Self.projection(for: entries)
  }

  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: 1 / 30,
        paused: reduceMotion || !hasAnimatedRing
      )
    ) { context in
      iconRow(at: context.date)
    }
    .frame(width: 72, height: 27, alignment: .trailing)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.32),
      value: projection
    )
    .accessibilityHidden(true)
  }

  private func iconRow(at date: Date) -> some View {
    HStack(spacing: -4) {
      if projection.overflowCount > 0 {
        Text("+\(projection.overflowCount)")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .foregroundStyle(.secondary)
          .frame(width: 21, height: 21)
          .background(.white.opacity(0.06), in: Circle())
          .overlay {
            Circle()
              .stroke(.secondary.opacity(0.32), lineWidth: 1)
          }
      }
      ForEach(Array(projection.entries.reversed())) { entry in
        AgentIslandProjectedIcon(
          entry: entry,
          pointSize: 21,
          animationDate: date,
          reduceMotion: reduceMotion
        )
        .transition(iconTransition)
      }
    }
  }

  private var hasAnimatedRing: Bool {
    projection.entries.contains {
      AgentIslandRingPresentation.presentation(for: $0.displayState).animates
    }
  }

  private var iconTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .offset(x: 5)
      .combined(with: .scale(scale: 0.55, anchor: .trailing))
      .combined(with: .opacity)
  }

  static func projection(for entries: [ActiveAgentEntry]) -> Projection {
    let ordered = entries.enumerated()
      .sorted { lhs, rhs in
        let lhsPriority = lhs.element.displayState.islandProjectionPriority
        let rhsPriority = rhs.element.displayState.islandProjectionPriority
        if lhsPriority != rhsPriority {
          return lhsPriority < rhsPriority
        }
        if lhs.element.lastChangedAt != rhs.element.lastChangedAt {
          return lhs.element.lastChangedAt > rhs.element.lastChangedAt
        }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
    let visibleLimit =
      ordered.count > maximumVisibleIcons ? maximumVisibleIcons - 1 : maximumVisibleIcons
    return Projection(
      entries: Array(ordered.prefix(visibleLimit)),
      overflowCount: max(0, ordered.count - visibleLimit)
    )
  }
}

struct AgentIslandRingPresentation: Equatable {
  let animates: Bool
  let rotationDuration: TimeInterval

  static func presentation(for state: AgentDisplayState) -> Self {
    switch state {
    case .working:
      return Self(animates: true, rotationDuration: 2.6)
    case .blocked:
      return Self(animates: true, rotationDuration: 1.35)
    case .done:
      return Self(animates: true, rotationDuration: 3.4)
    case .idle:
      return Self(animates: false, rotationDuration: 0)
    }
  }
}

private struct AgentIslandProjectedIcon: View {
  let entry: ActiveAgentEntry
  let pointSize: CGFloat
  let animationDate: Date
  let reduceMotion: Bool

  var body: some View {
    ZStack {
      Circle()
        .fill(.white.opacity(0.06))
      Group {
        if let source = entry.iconSource {
          TabIconImage(rawName: source.storageString, pointSize: pointSize - 5)
        } else {
          Image(systemName: "sparkle")
            .font(.system(size: pointSize * 0.56, weight: .semibold))
            .accessibilityHidden(true)
        }
      }
      .foregroundStyle(.white.opacity(0.92))
    }
    .frame(width: pointSize, height: pointSize)
    .overlay {
      AgentIslandStateRing(
        state: entry.displayState,
        animationDate: animationDate,
        reduceMotion: reduceMotion
      )
    }
    .padding(2)
  }
}

private struct AgentIslandStateRing: View {
  let state: AgentDisplayState
  let animationDate: Date
  let reduceMotion: Bool

  var body: some View {
    let presentation = AgentIslandRingPresentation.presentation(for: state)
    ring(
      angle: reduceMotion ? .zero : rotationAngle(at: animationDate, presentation: presentation),
      presentation: presentation
    )
  }

  private func ring(
    angle: Angle,
    presentation: AgentIslandRingPresentation
  ) -> some View {
    ZStack {
      Circle()
        .stroke(
          state.foregroundStyle.opacity(presentation.animates ? 0.2 : 0.42),
          lineWidth: presentation.animates ? 1.1 : 1
        )
      if presentation.animates {
        Circle()
          .stroke(
            AngularGradient(
              stops: [
                .init(color: state.foregroundStyle.opacity(0.08), location: 0),
                .init(color: state.foregroundStyle.opacity(0.34), location: 0.18),
                .init(color: state.foregroundStyle, location: 0.36),
                .init(color: state.foregroundStyle.opacity(0.28), location: 0.62),
                .init(color: state.foregroundStyle.opacity(0.72), location: 0.82),
                .init(color: state.foregroundStyle.opacity(0.08), location: 1),
              ],
              center: .center
            ),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
          )
          .rotationEffect(angle)
          .shadow(color: state.foregroundStyle.opacity(0.3), radius: 1.4)
      }
    }
  }

  private func rotationAngle(
    at date: Date,
    presentation: AgentIslandRingPresentation
  ) -> Angle {
    guard presentation.animates else { return .zero }
    let progress =
      date.timeIntervalSinceReferenceDate
      .truncatingRemainder(dividingBy: presentation.rotationDuration)
      / presentation.rotationDuration
    return .degrees(progress * 360)
  }
}
