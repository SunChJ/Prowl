import SwiftUI

/// A compact black-cat animation used as Agent Island's low-priority Working identity.
struct HeixiuWorkingIndicator: View {
  struct Motion: Equatable {
    let tailOpacity: CGFloat
    let ballOpacity: CGFloat
    let ballOffset: CGSize
    let ballScale: CGFloat
    let tailWave: CGFloat

    static let attached = Motion(
      tailOpacity: 1,
      ballOpacity: 0,
      ballOffset: .zero,
      ballScale: 0,
      tailWave: 0
    )
  }

  static let cycleDuration: TimeInterval = 3.6
  static let frameDuration: TimeInterval = 0.1

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let motionOverride: Motion?

  init(motion: Motion? = nil) {
    motionOverride = motion
  }

  var body: some View {
    Group {
      if let motionOverride {
        artwork(motion: motionOverride)
      } else if reduceMotion {
        artwork(motion: .attached)
      } else {
        TimelineView(.periodic(from: .now, by: Self.frameDuration)) { context in
          artwork(motion: Self.motion(at: context.date))
        }
      }
    }
    .frame(width: 42, height: 18)
    .accessibilityHidden(true)
  }

  static func motion(at date: Date) -> Motion {
    let elapsed = date.timeIntervalSinceReferenceDate
    let remainder = elapsed.truncatingRemainder(dividingBy: cycleDuration)
    let normalizedTime = (remainder >= 0 ? remainder : remainder + cycleDuration) / cycleDuration

    switch normalizedTime {
    case ..<0.42:
      return Motion(
        tailOpacity: 1,
        ballOpacity: 0,
        ballOffset: .zero,
        ballScale: 0,
        tailWave: CGFloat(sin((normalizedTime / 0.42) * .pi * 2)) * 0.45
      )
    case ..<0.58:
      let progress = smoothstep((normalizedTime - 0.42) / 0.16)
      return Motion(
        tailOpacity: 1 - progress,
        ballOpacity: progress,
        ballOffset: CGSize(width: progress, height: -4 * progress),
        ballScale: progress,
        tailWave: 0
      )
    case ..<0.78:
      let progress = CGFloat((normalizedTime - 0.58) / 0.2)
      let arc = sin(progress * .pi)
      return Motion(
        tailOpacity: 0,
        ballOpacity: 1,
        ballOffset: CGSize(width: 1 + (arc * 1.4), height: -4 - (arc * 0.8)),
        ballScale: 1,
        tailWave: 0
      )
    case ..<0.94:
      let progress = smoothstep((normalizedTime - 0.78) / 0.16)
      return Motion(
        tailOpacity: progress,
        ballOpacity: 1 - progress,
        ballOffset: CGSize(width: 1 - progress, height: -4 * (1 - progress)),
        ballScale: 1 - progress,
        tailWave: 0
      )
    default:
      return .attached
    }
  }

  private static func smoothstep(_ value: Double) -> CGFloat {
    let clamped = min(max(value, 0), 1)
    return CGFloat(clamped * clamped * (3 - (2 * clamped)))
  }

  private func artwork(motion: Motion) -> some View {
    Canvas { context, _ in
      let backdrop = Path(
        roundedRect: CGRect(x: 0.5, y: 0.75, width: 41, height: 16.5),
        cornerRadius: 8.25
      )
      context.fill(backdrop, with: .color(.white.opacity(0.72)))
      context.stroke(backdrop, with: .color(.orange.opacity(0.48)), lineWidth: 0.75)

      drawTail(in: &context, motion: motion)
      drawBody(in: &context)
      drawBall(in: &context, motion: motion)
    }
  }

  private func drawTail(in context: inout GraphicsContext, motion: Motion) {
    var tail = Path()
    tail.move(to: CGPoint(x: 13, y: 7.5 + motion.tailWave))
    tail.addCurve(
      to: CGPoint(x: 3.7, y: 10.6 + motion.tailWave),
      control1: CGPoint(x: 9.5, y: 5.2 + motion.tailWave),
      control2: CGPoint(x: 8.2, y: 12.2 + motion.tailWave)
    )

    var tailContext = context
    tailContext.opacity = motion.tailOpacity
    tailContext.stroke(
      tail,
      with: .color(.black.opacity(0.94)),
      style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
    )
  }

  private func drawBody(in context: inout GraphicsContext) {
    var body = Path()
    body.move(to: CGPoint(x: 11.5, y: 7.2))
    body.addCurve(
      to: CGPoint(x: 28, y: 6.1),
      control1: CGPoint(x: 15, y: 3.2),
      control2: CGPoint(x: 23.5, y: 3.6)
    )
    body.addLine(to: CGPoint(x: 30.2, y: 3.1))
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

    let eye = Path(ellipseIn: CGRect(x: 33.3, y: 7.3, width: 1.35, height: 1.35))
    context.fill(eye, with: .color(.white.opacity(0.92)))
  }

  private func drawBall(in context: inout GraphicsContext, motion: Motion) {
    let diameter = 3.5 * motion.ballScale
    let center = CGPoint(
      x: 3.7 + motion.ballOffset.width,
      y: 10.6 + motion.ballOffset.height
    )
    let ball = Path(
      ellipseIn: CGRect(
        x: center.x - (diameter / 2),
        y: center.y - (diameter / 2),
        width: diameter,
        height: diameter
      )
    )

    var ballContext = context
    ballContext.opacity = motion.ballOpacity
    ballContext.fill(ball, with: .color(.black.opacity(0.96)))
  }
}

#Preview {
  HStack(spacing: 8) {
    HeixiuWorkingIndicator(motion: .attached)
    HeixiuWorkingIndicator(
      motion: HeixiuWorkingIndicator.motion(
        at: Date(timeIntervalSinceReferenceDate: HeixiuWorkingIndicator.cycleDuration * 0.5)
      )
    )
    HeixiuWorkingIndicator(
      motion: HeixiuWorkingIndicator.motion(
        at: Date(timeIntervalSinceReferenceDate: HeixiuWorkingIndicator.cycleDuration * 0.68)
      )
    )
  }
  .padding()
  .background(.black)
}
