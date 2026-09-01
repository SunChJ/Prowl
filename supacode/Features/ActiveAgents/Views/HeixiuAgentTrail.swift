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
    HStack(spacing: -3) {
      HStack(spacing: 1) {
        if projection.overflowCount > 0 {
          Text("+\(projection.overflowCount)")
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .frame(width: 18, height: 18)
            .background(.white.opacity(0.12), in: Circle())
        }
        ForEach(Array(projection.entries.reversed())) { entry in
          AgentStatusIcon(
            entry: entry,
            pointSize: 16,
            indicatorSize: 7,
            showsPlate: true,
            animatesWorking: true
          )
          .transition(
            reduceMotion
              ? .opacity
              : .scale(scale: 0.35, anchor: .trailing).combined(with: .opacity)
          )
        }
      }
      HeixiuCatPose(state: projection.dominantState)
        .frame(width: 39, height: 18)
    }
    .frame(width: 92, height: 20, alignment: .trailing)
    .animation(
      reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.3),
      value: projection
    )
    .accessibilityHidden(true)
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

private struct HeixiuCatPose: View {
  let state: AgentDisplayState

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Canvas { context, _ in
        drawTail(in: &context)
        if state == .idle {
          drawSleepingBody(in: &context)
        } else {
          drawProwlingBody(in: &context)
        }
      }
      stateAccent
    }
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
        .foregroundStyle(.white.opacity(0.7))
        .offset(x: -1, y: 1)
    case .working, .blocked:
      EmptyView()
    }
  }

  private func drawTail(in context: inout GraphicsContext) {
    var tail = Path()
    tail.move(to: CGPoint(x: state == .idle ? 15 : 13, y: state == .idle ? 9.5 : 7.5))
    switch state {
    case .working:
      tail.addCurve(
        to: CGPoint(x: 3.7, y: 10.6),
        control1: CGPoint(x: 9.5, y: 5.2),
        control2: CGPoint(x: 8.2, y: 12.2)
      )
    case .blocked:
      tail.addCurve(
        to: CGPoint(x: 3.7, y: 5.2),
        control1: CGPoint(x: 9.5, y: 6.8),
        control2: CGPoint(x: 7, y: 5.3)
      )
    case .done:
      tail.addCurve(
        to: CGPoint(x: 3.7, y: 4.2),
        control1: CGPoint(x: 8.5, y: 8.8),
        control2: CGPoint(x: 8.4, y: 2.5)
      )
    case .idle:
      tail.addCurve(
        to: CGPoint(x: 4, y: 13.5),
        control1: CGPoint(x: 9, y: 9.5),
        control2: CGPoint(x: 9, y: 14.5)
      )
    }
    context.stroke(
      tail,
      with: .color(.white.opacity(0.62)),
      style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
    )
    context.stroke(
      tail,
      with: .color(.black.opacity(0.94)),
      style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
    )
  }

  private func drawProwlingBody(in context: inout GraphicsContext) {
    let earTipY = state == .blocked ? 1.8 : 3.1
    var body = Path()
    body.move(to: CGPoint(x: 11.5, y: 7.2))
    body.addCurve(
      to: CGPoint(x: 28, y: 6.1),
      control1: CGPoint(x: 15, y: 3.2),
      control2: CGPoint(x: 23.5, y: 3.6)
    )
    body.addLine(to: CGPoint(x: 30.2, y: earTipY))
    body.addLine(to: CGPoint(x: 31.1, y: 6))
    body.addCurve(
      to: CGPoint(x: 37.2, y: 9.4),
      control1: CGPoint(x: 34.2, y: 5.7),
      control2: CGPoint(x: 35.4, y: 7.2)
    )
    body.addCurve(
      to: CGPoint(x: 32.2, y: 11.4),
      control1: CGPoint(x: 36, y: 11.1),
      control2: CGPoint(x: 34, y: 11.5)
    )
    body.addLine(to: CGPoint(x: 34, y: 15.2))
    body.addLine(to: CGPoint(x: 29.8, y: 15.2))
    body.addLine(to: CGPoint(x: 27.5, y: 11.6))
    body.addLine(to: CGPoint(x: 21.7, y: 12))
    body.addLine(to: CGPoint(x: 24, y: 15.2))
    body.addLine(to: CGPoint(x: 19.3, y: 15.2))
    body.addLine(to: CGPoint(x: 16.4, y: 12.1))
    body.addLine(to: CGPoint(x: 11.6, y: 11.5))
    body.addLine(to: CGPoint(x: 10, y: 15.2))
    body.addLine(to: CGPoint(x: 5.8, y: 15.2))
    body.addLine(to: CGPoint(x: 8, y: 10.7))
    body.closeSubpath()
    context.fill(body, with: .color(.black.opacity(0.94)))
    context.stroke(
      body,
      with: .color(.white.opacity(0.62)),
      style: StrokeStyle(lineWidth: 0.8, lineJoin: .round)
    )

    let eyeSize: CGFloat = state == .blocked ? 1.7 : 1.35
    let eye = Path(ellipseIn: CGRect(x: 33.3, y: 7.2, width: eyeSize, height: eyeSize))
    context.fill(eye, with: .color(.white.opacity(0.94)))
  }

  private func drawSleepingBody(in context: inout GraphicsContext) {
    let body = Path(ellipseIn: CGRect(x: 9, y: 5.2, width: 25, height: 10.5))
    context.fill(body, with: .color(.black.opacity(0.94)))
    context.stroke(body, with: .color(.white.opacity(0.62)), lineWidth: 0.8)

    var head = Path()
    head.move(to: CGPoint(x: 28, y: 9))
    head.addLine(to: CGPoint(x: 30.5, y: 5))
    head.addLine(to: CGPoint(x: 32, y: 8.2))
    head.addCurve(
      to: CGPoint(x: 37, y: 11.2),
      control1: CGPoint(x: 34.5, y: 7.4),
      control2: CGPoint(x: 36.2, y: 9)
    )
    head.addCurve(
      to: CGPoint(x: 29, y: 13.6),
      control1: CGPoint(x: 35.2, y: 13.6),
      control2: CGPoint(x: 31.5, y: 14)
    )
    head.closeSubpath()
    context.fill(head, with: .color(.black.opacity(0.94)))
    context.stroke(
      head,
      with: .color(.white.opacity(0.62)),
      style: StrokeStyle(lineWidth: 0.8, lineJoin: .round)
    )

    var closedEye = Path()
    closedEye.move(to: CGPoint(x: 33, y: 10.4))
    closedEye.addCurve(
      to: CGPoint(x: 35.2, y: 10.4),
      control1: CGPoint(x: 33.7, y: 11),
      control2: CGPoint(x: 34.5, y: 11)
    )
    context.stroke(
      closedEye,
      with: .color(.white.opacity(0.9)),
      style: StrokeStyle(lineWidth: 0.8, lineCap: .round)
    )
  }
}
