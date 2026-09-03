import AppKit
import QuartzCore
import SwiftUI

/// A compact, island-owned projection of the real Active Agents roster.
struct AgentIslandIconCluster: View {
  struct Projection: Equatable {
    let entries: [ActiveAgentEntry]
    let overflowCount: Int

    var identity: ProjectionIdentity {
      ProjectionIdentity(ids: entries.map(\.id), overflowCount: overflowCount)
    }
  }

  /// What the swap animation reacts to. Entries refresh every second (titles, timestamps), and
  /// keying the animation on the full value would open an animated transaction on each refresh,
  /// animating any concurrent layout shift; only membership, order, and overflow move icons.
  struct ProjectionIdentity: Equatable {
    let ids: [ActiveAgentEntry.ID]
    let overflowCount: Int
  }

  private static let maximumVisibleIcons = 3

  let projection: Projection
  /// Icon diameter; the notched bar passes a smaller size because it is only as tall as the cutout.
  let pointSize: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(entries: [ActiveAgentEntry], pointSize: CGFloat = 21) {
    projection = Self.projection(for: entries)
    self.pointSize = pointSize
  }

  var body: some View {
    iconRow
      // Each icon is a `pointSize + 2` circle with 2pt of padding, so the cluster is exactly one
      // padded icon tall.
      .frame(width: 78, height: pointSize + 6, alignment: .trailing)
      .animation(
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.32),
        value: projection.identity
      )
      .accessibilityHidden(true)
  }

  private var iconRow: some View {
    ZStack(alignment: .bottomTrailing) {
      HStack(spacing: -4) {
        ForEach(projection.entries) { entry in
          AgentIslandRuntimeIcon(
            entry: entry,
            pointSize: pointSize
          )
          .transition(iconTransition)
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)

      if projection.overflowCount > 0 {
        Text("+\(projection.overflowCount)")
          .font(.system(size: 8, weight: .bold, design: .rounded))
          .foregroundStyle(.white.opacity(0.82))
          .padding(.horizontal, 2)
          .background(.black.opacity(0.92), in: Capsule())
          .offset(x: 2, y: 2)
          .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottomTrailing))
      }
    }
  }

  private var iconTransition: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .offset(x: -5)
      .combined(with: .scale(scale: 0.55, anchor: .leading))
      .combined(with: .opacity)
  }

  static func projection(for entries: [ActiveAgentEntry]) -> Projection {
    let ordered = entries.enumerated()
      .sorted { lhs, rhs in
        let lhsIsIdle = lhs.element.displayState == .idle
        let rhsIsIdle = rhs.element.displayState == .idle
        if lhsIsIdle != rhsIsIdle {
          return !lhsIsIdle
        }
        if lhs.element.lastChangedAt != rhs.element.lastChangedAt {
          return lhs.element.lastChangedAt > rhs.element.lastChangedAt
        }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
    return Projection(
      entries: Array(ordered.prefix(maximumVisibleIcons)),
      overflowCount: max(0, ordered.count - maximumVisibleIcons)
    )
  }
}

struct AgentIslandRingPresentation: Equatable {
  let animates: Bool
  let breathingDuration: TimeInterval
  let driftDuration: TimeInterval

  static func presentation(for state: AgentDisplayState) -> Self {
    switch state {
    case .working:
      return Self(animates: true, breathingDuration: 1.8, driftDuration: 14)
    case .blocked:
      return Self(animates: true, breathingDuration: 1.2, driftDuration: 11)
    case .done:
      return Self(animates: true, breathingDuration: 2.4, driftDuration: 17)
    case .idle:
      return Self(animates: false, breathingDuration: 0, driftDuration: 0)
    }
  }
}

struct AgentIslandRuntimeIcon: View {
  let entry: ActiveAgentEntry
  let pointSize: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    // The ring circle is one point wider in radius than the glyph budget so the glyph and the
    // breathing ring do not touch.
    .frame(width: pointSize + 2, height: pointSize + 2)
    .overlay {
      AgentIslandStateRing(
        state: entry.displayState,
        reduceMotion: reduceMotion
      )
      .allowsHitTesting(false)
    }
    .padding(2)
    .accessibilityHidden(true)
  }
}

private struct AgentIslandStateRing: NSViewRepresentable {
  let state: AgentDisplayState
  let reduceMotion: Bool

  func makeNSView(context: Context) -> AgentIslandStateRingView {
    let view = AgentIslandStateRingView()
    view.update(state: state, reduceMotion: reduceMotion)
    return view
  }

  func updateNSView(_ nsView: AgentIslandStateRingView, context: Context) {
    nsView.update(state: state, reduceMotion: reduceMotion)
  }
}

@MainActor
final class AgentIslandStateRingView: NSView {
  private static let breathingAnimationKey = "agent-island-ring-breathing"
  private static let driftAnimationKey = "agent-island-ring-drift"

  private let baseRingLayer = CAShapeLayer()
  private let breathingRingLayer = CALayer()
  private let animatedRingLayer = CAGradientLayer()
  private let animatedRingMask = CAShapeLayer()
  private var breathingDuration: TimeInterval?
  private var driftDuration: TimeInterval?
  private var currentState = AgentDisplayState.idle
  private var currentReduceMotion = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    baseRingLayer.fillColor = NSColor.clear.cgColor
    animatedRingLayer.type = .conic
    animatedRingLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
    animatedRingLayer.endPoint = CGPoint(x: 0.5, y: 0)
    animatedRingLayer.mask = animatedRingMask
    animatedRingMask.fillColor = NSColor.clear.cgColor
    animatedRingMask.strokeColor = NSColor.white.cgColor
    animatedRingMask.lineWidth = 2.2
    animatedRingMask.lineCap = .round
    breathingRingLayer.addSublayer(animatedRingLayer)
    layer?.addSublayer(baseRingLayer)
    layer?.addSublayer(breathingRingLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let ringBounds = bounds.insetBy(dx: 1.2, dy: 1.2)
    let path = CGPath(ellipseIn: ringBounds, transform: nil)
    baseRingLayer.frame = bounds
    baseRingLayer.path = path
    breathingRingLayer.frame = bounds
    animatedRingLayer.frame = breathingRingLayer.bounds
    animatedRingMask.frame = animatedRingLayer.bounds
    animatedRingMask.path = path
    CATransaction.commit()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateContentsScale()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateContentsScale()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyPresentation()
  }

  func update(state: AgentDisplayState, reduceMotion: Bool) {
    currentState = state
    currentReduceMotion = reduceMotion
    applyPresentation()
  }

  var isBreathingActive: Bool {
    breathingRingLayer.animation(forKey: Self.breathingAnimationKey) != nil
  }

  var isDriftActive: Bool {
    animatedRingLayer.animation(forKey: Self.driftAnimationKey) != nil
  }

  private func applyPresentation() {
    let presentation = AgentIslandRingPresentation.presentation(for: currentState)
    let color = resolvedColor(for: currentState)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    baseRingLayer.strokeColor = color.withAlphaComponent(presentation.animates ? 0.16 : 0.42).cgColor
    baseRingLayer.lineWidth = presentation.animates ? 1.1 : 1
    breathingRingLayer.isHidden = !presentation.animates
    animatedRingLayer.colors = Self.gradientAlphas.map {
      color.withAlphaComponent($0).cgColor
    }
    animatedRingLayer.locations = Self.gradientLocations
    animatedRingLayer.shadowColor = color.cgColor
    animatedRingLayer.shadowOpacity = presentation.animates ? 0.42 : 0
    animatedRingLayer.shadowRadius = 1.8
    animatedRingLayer.shadowOffset = .zero
    CATransaction.commit()

    if presentation.animates, !currentReduceMotion {
      startBreathing(duration: presentation.breathingDuration)
      startDrift(duration: presentation.driftDuration)
    } else {
      stopAnimations()
    }
  }

  private func startBreathing(duration: TimeInterval) {
    guard breathingDuration != duration || !isBreathingActive else { return }

    let opacity = CAKeyframeAnimation(keyPath: "opacity")
    opacity.values = [1, 0.48, 1]
    opacity.keyTimes = [0, 0.5, 1]
    opacity.timingFunctions = Self.breathingTimingFunctions
    opacity.duration = duration

    let scale = CAKeyframeAnimation(keyPath: "transform.scale")
    scale.values = [1, 0.94, 1]
    scale.keyTimes = [0, 0.5, 1]
    scale.timingFunctions = Self.breathingTimingFunctions
    scale.duration = duration

    let animation = CAAnimationGroup()
    animation.animations = [opacity, scale]
    animation.duration = duration
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    breathingRingLayer.add(animation, forKey: Self.breathingAnimationKey)
    breathingDuration = duration
  }

  private func startDrift(duration: TimeInterval) {
    guard driftDuration != duration || !isDriftActive else { return }
    let animation = CABasicAnimation(keyPath: "transform.rotation.z")
    animation.fromValue = 0
    animation.toValue = Double.pi * 2
    animation.duration = duration
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    animatedRingLayer.add(animation, forKey: Self.driftAnimationKey)
    driftDuration = duration
  }

  private func stopAnimations() {
    breathingRingLayer.removeAnimation(forKey: Self.breathingAnimationKey)
    animatedRingLayer.removeAnimation(forKey: Self.driftAnimationKey)
    breathingDuration = nil
    driftDuration = nil
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    breathingRingLayer.opacity = 1
    breathingRingLayer.transform = CATransform3DIdentity
    animatedRingLayer.transform = CATransform3DIdentity
    CATransaction.commit()
  }

  private func updateContentsScale() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    baseRingLayer.contentsScale = scale
    breathingRingLayer.contentsScale = scale
    animatedRingLayer.contentsScale = scale
    animatedRingMask.contentsScale = scale
  }

  private func resolvedColor(for state: AgentDisplayState) -> NSColor {
    var color: NSColor?
    effectiveAppearance.performAsCurrentDrawingAppearance {
      color =
        switch state {
        case .working:
          .systemOrange
        case .blocked:
          .systemRed
        case .done:
          .systemBlue
        case .idle:
          .secondaryLabelColor
        }
    }
    return color ?? .secondaryLabelColor
  }

  private static let gradientAlphas: [CGFloat] = [0.48, 0.68, 0.92, 0.7, 0.82, 0.48]
  private static let gradientLocations: [NSNumber] = [0, 0.18, 0.36, 0.62, 0.82, 1]
  private static let breathingTimingFunctions = [
    CAMediaTimingFunction(name: .easeInEaseOut),
    CAMediaTimingFunction(name: .easeInEaseOut),
  ]
}
