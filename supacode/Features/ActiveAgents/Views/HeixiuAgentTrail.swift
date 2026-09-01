import SwiftUI

/// Heixiu is the island's persistent identity; the tail projects the real agent roster.
struct HeixiuAgentTrail: View {
  struct Projection: Equatable {
    let entries: [ActiveAgentEntry]
    let overflowCount: Int
    let dominantState: AgentDisplayState
  }

  private static let maximumVisibleIcons = 3

  let projection: Projection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(entries: [ActiveAgentEntry]) {
    projection = Self.projection(for: entries)
  }

  var body: some View {
    HStack(spacing: -4) {
      HStack(spacing: 1) {
        if projection.overflowCount > 0 {
          Text("+\(projection.overflowCount)")
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .background(.white.opacity(0.07), in: Circle())
            .overlay {
              Circle()
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
        }
        ForEach(Array(projection.entries.reversed())) { entry in
          AgentStatusIcon(
            entry: entry,
            pointSize: 15,
            indicatorSize: 6,
            showsPlate: true,
            showsStatusSymbol: false,
            animatesWorking: true
          )
          .transition(tailOriginTransition)
        }
      }
      HeixiuCatPose(state: projection.dominantState)
        .frame(width: 44, height: 20)
    }
    .frame(width: 92, height: 20, alignment: .trailing)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.3),
      value: projection
    )
    .accessibilityHidden(true)
  }

  private var tailOriginTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .asymmetric(
      insertion: .offset(x: 8)
        .combined(with: .scale(scale: 0.18, anchor: .trailing))
        .combined(with: .opacity),
      removal: .offset(y: -4)
        .combined(with: .scale(scale: 0.65))
        .combined(with: .opacity)
    )
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
      overflowCount: max(0, ordered.count - visibleLimit),
      dominantState: ordered.first?.displayState ?? .idle
    )
  }
}

struct ProwlCatGeometry: Equatable {
  let tailLift: CGFloat
  let headLift: CGFloat
  let forelegReach: CGFloat

  static func geometry(for state: AgentDisplayState) -> Self {
    switch state {
    case .working:
      return Self(tailLift: 0, headLift: 0, forelegReach: 1.2)
    case .blocked:
      return Self(tailLift: 5.5, headLift: 1.8, forelegReach: 0)
    case .done:
      return Self(tailLift: 3, headLift: 0.9, forelegReach: 0.8)
    case .idle:
      return Self(tailLift: -1.5, headLift: -0.6, forelegReach: 0)
    }
  }
}

private struct HeixiuCatPose: View {
  let state: AgentDisplayState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .topTrailing) {
      animatedCat
      stateAccent
    }
  }

  @ViewBuilder
  private var animatedCat: some View {
    if state == .working, !reduceMotion {
      catBody
        .phaseAnimator([false, true]) { content, advancing in
          content
            .scaleEffect(
              x: advancing ? 1.018 : 0.988,
              y: advancing ? 0.985 : 1.01,
              anchor: .bottom
            )
            .offset(x: advancing ? 0.7 : -0.35, y: advancing ? -0.2 : 0.15)
        } animation: { _ in
          .easeInOut(duration: 1.1)
        }
    } else {
      catBody
    }
  }

  private var catBody: some View {
    let geometry = ProwlCatGeometry.geometry(for: state)
    return ProwlCatSilhouette(
      tailLift: geometry.tailLift,
      headLift: geometry.headLift,
      forelegReach: geometry.forelegReach
    )
    .fill(
      LinearGradient(
        colors: [Color("ProwlAccent").opacity(0.72), Color("ProwlAccent")],
        startPoint: .leading,
        endPoint: .trailing
      )
    )
    .shadow(color: Color("ProwlAccent").opacity(0.22), radius: 1.5)
    .overlay(alignment: .topTrailing) {
      Circle()
        .fill(.white.opacity(0.94))
        .frame(width: 1.6, height: 1.6)
        .offset(x: -3.5, y: 9.8 - geometry.headLift)
    }
    .animation(.spring(duration: 0.32, bounce: 0.32), value: geometry)
  }

  @ViewBuilder
  private var stateAccent: some View {
    switch state {
    case .done:
      Image(systemName: "sparkles")
        .font(.system(size: 5, weight: .bold))
        .foregroundStyle(.blue)
        .offset(x: -1, y: 1)
        .accessibilityHidden(true)
    case .idle:
      Text("z")
        .font(.system(size: 6, weight: .bold, design: .rounded))
        .foregroundStyle(.secondary)
        .offset(x: -1, y: 1)
    case .working, .blocked:
      EmptyView()
    }
  }
}

private struct ProwlCatSilhouette: Shape {
  var tailLift: CGFloat
  var headLift: CGFloat
  var forelegReach: CGFloat

  var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
    get { AnimatablePair(tailLift, AnimatablePair(headLift, forelegReach)) }
    set {
      tailLift = newValue.first
      headLift = newValue.second.first
      forelegReach = newValue.second.second
    }
  }

  func path(in rect: CGRect) -> Path {
    let scaleX = rect.width / 48
    let scaleY = rect.height / 22
    let tailY = 13 - tailLift
    let headY = -headLift
    let point: (CGFloat, CGFloat) -> CGPoint = { xPosition, yPosition in
      CGPoint(x: rect.minX + xPosition * scaleX, y: rect.minY + yPosition * scaleY)
    }

    var path = Path()
    addBackAndHead(to: &path, point: point, tailY: tailY, headY: headY)
    addLegsAndTail(to: &path, point: point, tailY: tailY)
    path.closeSubpath()
    return path
  }

  private func addBackAndHead(
    to path: inout Path,
    point: (CGFloat, CGFloat) -> CGPoint,
    tailY: CGFloat,
    headY: CGFloat
  ) {
    path.move(to: point(1, tailY))
    path.addCurve(
      to: point(12, 11.5),
      control1: point(4, tailY + 1.2),
      control2: point(9, 14.2)
    )
    path.addCurve(
      to: point(18, 6.5),
      control1: point(14.8, 10.4),
      control2: point(15.4, 7.5)
    )
    path.addCurve(
      to: point(28, 5.4),
      control1: point(21.8, 3.7),
      control2: point(25.2, 4.3)
    )
    path.addCurve(
      to: point(34, 8.8 + headY),
      control1: point(31, 5.8),
      control2: point(31.7, 8.3 + headY)
    )
    path.addLine(to: point(36.5, 4 + headY))
    path.addCurve(
      to: point(37.5, 8.6 + headY),
      control1: point(37, 4.4 + headY),
      control2: point(37.4, 6.8 + headY)
    )
    path.addLine(to: point(41, 6.1 + headY))
    path.addCurve(
      to: point(40.3, 10 + headY),
      control1: point(41.2, 7.1 + headY),
      control2: point(40.8, 8.7 + headY)
    )
    path.addCurve(
      to: point(45.2, 12.1 + headY),
      control1: point(42.5, 10 + headY),
      control2: point(44.1, 10.9 + headY)
    )
    path.addCurve(
      to: point(47, 14.3 + headY),
      control1: point(45.5, 13.2 + headY),
      control2: point(46.2, 13.7 + headY)
    )
    path.addCurve(
      to: point(43.1, 16.5 + headY),
      control1: point(46, 15.7 + headY),
      control2: point(44.7, 16.4 + headY)
    )
  }

  private func addLegsAndTail(
    to path: inout Path,
    point: (CGFloat, CGFloat) -> CGPoint,
    tailY: CGFloat
  ) {
    path.addCurve(
      to: point(47 + forelegReach, 20.4),
      control1: point(44.1, 17.9),
      control2: point(46.2 + forelegReach, 19.2)
    )
    path.addCurve(
      to: point(43.2, 21),
      control1: point(48.5 + forelegReach, 21),
      control2: point(45.5, 21.1)
    )
    path.addLine(to: point(37.3, 17))
    path.addCurve(
      to: point(39.4, 20.7),
      control1: point(37.5, 18.2),
      control2: point(39, 19.5)
    )
    path.addCurve(
      to: point(34.5, 20.9),
      control1: point(38.5, 21.2),
      control2: point(35.3, 21.1)
    )
    path.addLine(to: point(31.5, 16.1))
    path.addCurve(
      to: point(25.3, 15.8),
      control1: point(29.2, 16.6),
      control2: point(27, 16.6)
    )
    path.addCurve(
      to: point(28.2, 20.7),
      control1: point(25.2, 17.4),
      control2: point(27.6, 19.2)
    )
    path.addCurve(
      to: point(23.2, 20.9),
      control1: point(27.1, 21.2),
      control2: point(24.2, 21.2)
    )
    path.addLine(to: point(18.5, 16.4))
    path.addCurve(
      to: point(15.4, 20.8),
      control1: point(18.1, 18.1),
      control2: point(16.7, 19.6)
    )
    path.addCurve(
      to: point(10.7, 20.7),
      control1: point(14.2, 21.2),
      control2: point(11.5, 21.1)
    )
    path.addCurve(
      to: point(11.4, 15),
      control1: point(9.6, 19.2),
      control2: point(10.4, 16.8)
    )
    path.addCurve(
      to: point(1, tailY + 2.5),
      control1: point(8.4, 16.1),
      control2: point(3.5, tailY + 3.8)
    )
    path.addCurve(
      to: point(1, tailY),
      control1: point(0.1, tailY + 2.1),
      control2: point(0.1, tailY + 0.4)
    )
  }
}
