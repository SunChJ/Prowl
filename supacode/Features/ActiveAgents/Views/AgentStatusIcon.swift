import SwiftUI

/// The real agent icon with a compact, state-owned lamp in its lower-right corner.
struct AgentStatusIcon: View {
  let entry: ActiveAgentEntry
  var pointSize: CGFloat = 20
  var indicatorSize: CGFloat = 9
  var showsPlate = false
  var showsStatusSymbol = true
  var animatesWorking = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      icon
      animatedStatusLamp
        .offset(x: 1, y: 1)
    }
    .frame(width: pointSize + 2, height: pointSize + 2)
    .accessibilityHidden(true)
  }

  private var icon: some View {
    ZStack {
      if showsPlate {
        Circle()
          .fill(entry.displayState.foregroundStyle.opacity(0.14))
          .overlay {
            Circle()
              .stroke(entry.displayState.foregroundStyle.opacity(0.48), lineWidth: 0.75)
          }
      }
      Group {
        if let source = entry.iconSource {
          TabIconImage(rawName: source.storageString, pointSize: pointSize - (showsPlate ? 4 : 2))
        } else {
          Image(systemName: "sparkle")
            .font(.system(size: pointSize * 0.58, weight: .semibold))
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
        }
      }
      .foregroundStyle(.white.opacity(0.94))
    }
    .frame(width: pointSize, height: pointSize)
  }

  @ViewBuilder
  private var animatedStatusLamp: some View {
    if animatesWorking, entry.displayState == .working, !reduceMotion {
      statusLamp
        .phaseAnimator([false, true]) { content, isLit in
          content
            .scaleEffect(isLit ? 1.12 : 0.88)
            .opacity(isLit ? 1 : 0.72)
        } animation: { _ in
          .easeInOut(duration: 0.8)
        }
    } else {
      statusLamp
    }
  }

  private var statusLamp: some View {
    ZStack {
      Circle()
        .fill(.black)
      Circle()
        .fill(entry.displayState.foregroundStyle)
        .padding(1)
      if showsStatusSymbol {
        Image(systemName: entry.displayState.statusSymbolName)
          .font(.system(size: indicatorSize * 0.48, weight: .bold))
          .foregroundStyle(.white)
          .accessibilityHidden(true)
      }
    }
    .frame(width: indicatorSize, height: indicatorSize)
    .overlay {
      Circle()
        .stroke(.white.opacity(0.3), lineWidth: 0.5)
    }
  }
}

extension AgentDisplayState {
  var label: String {
    switch self {
    case .working:
      return "Working"
    case .blocked:
      return "Blocked"
    case .done:
      return "Done"
    case .idle:
      return "Idle"
    }
  }

  var foregroundStyle: Color {
    switch self {
    case .working:
      return .orange
    case .blocked:
      return .red
    case .done:
      return .blue
    case .idle:
      return .secondary
    }
  }

  var statusSymbolName: String {
    switch self {
    case .working:
      return "pawprint.fill"
    case .blocked:
      return "exclamationmark"
    case .done:
      return "sparkles"
    case .idle:
      return "moon.zzz.fill"
    }
  }

  var islandProjectionPriority: Int {
    switch self {
    case .blocked:
      return 0
    case .done:
      return 1
    case .working:
      return 2
    case .idle:
      return 3
    }
  }
}
