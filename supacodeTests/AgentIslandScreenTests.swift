import CoreGraphics
import Testing

@testable import supacode

@MainActor
struct AgentIslandScreenTests {
  @Test func explicitDisplayWinsOverAutomaticCandidates() throws {
    let builtIn = screen(id: "built-in", isBuiltIn: true, hasNotch: true)
    let external = screen(id: "external", origin: CGPoint(x: -1_920, y: 0))

    let resolved = AgentIslandScreenLayout.resolve(
      preference: .display(id: external.id, name: external.name),
      screens: [builtIn, external],
      mainWindowScreenID: builtIn.id,
      mainScreenID: builtIn.id
    )

    #expect(try #require(resolved).id == external.id)
  }

  @Test func disconnectedDisplayTemporarilyFallsBackToAutomatic() throws {
    let builtIn = screen(id: "built-in", isBuiltIn: true, hasNotch: true)
    let mainWindow = screen(id: "main-window")

    let resolved = AgentIslandScreenLayout.resolve(
      preference: .display(id: "disconnected", name: "Studio Display"),
      screens: [builtIn, mainWindow],
      mainWindowScreenID: mainWindow.id,
      mainScreenID: builtIn.id
    )

    #expect(try #require(resolved).id == mainWindow.id)
  }

  @Test func automaticFallsBackThroughMainWindowBuiltInNotchAndMainScreen() throws {
    let mainWindow = screen(id: "main-window")
    let builtIn = screen(id: "built-in", isBuiltIn: true, hasNotch: true)
    let systemMain = screen(id: "system-main")

    let windowResolved = AgentIslandScreenLayout.resolve(
      preference: .automatic,
      screens: [systemMain, builtIn, mainWindow],
      mainWindowScreenID: mainWindow.id,
      mainScreenID: systemMain.id
    )
    #expect(try #require(windowResolved).id == mainWindow.id)

    let notchResolved = AgentIslandScreenLayout.resolve(
      preference: .automatic,
      screens: [systemMain, builtIn],
      mainWindowScreenID: nil,
      mainScreenID: systemMain.id
    )
    #expect(try #require(notchResolved).id == builtIn.id)

    let mainResolved = AgentIslandScreenLayout.resolve(
      preference: .automatic,
      screens: [mainWindow, systemMain],
      mainWindowScreenID: nil,
      mainScreenID: systemMain.id
    )
    #expect(try #require(mainResolved).id == systemMain.id)
  }

  @Test func notchedPanelPinsToPhysicalTopEdge() {
    let display = screen(
      id: "notched",
      origin: CGPoint(x: 0, y: 240),
      isBuiltIn: true,
      hasNotch: true
    )

    let frame = AgentIslandScreenLayout.panelFrame(
      contentSize: CGSize(width: 420, height: 180),
      screen: display
    )

    #expect(frame.midX == display.frame.midX)
    #expect(frame.maxY == display.frame.maxY)
  }

  @Test func floatingPillUsesVisibleTopAndSupportsNegativeCoordinates() {
    let display = screen(
      id: "external",
      origin: CGPoint(x: -2_560, y: -180),
      visibleTopInset: 32
    )

    let frame = AgentIslandScreenLayout.panelFrame(
      contentSize: CGSize(width: 420, height: 200),
      screen: display
    )

    #expect(frame.midX == display.frame.midX)
    #expect(
      abs(frame.maxY - (display.visibleFrame.maxY - AgentIslandScreenLayout.floatingTopOffset))
        < 0.001
    )
  }

  private func screen(
    id: String,
    origin: CGPoint = .zero,
    visibleTopInset: CGFloat = 24,
    isBuiltIn: Bool = false,
    hasNotch: Bool = false
  ) -> AgentIslandScreenDescriptor {
    let frame = CGRect(origin: origin, size: CGSize(width: 1_920, height: 1_080))
    return AgentIslandScreenDescriptor(
      id: id,
      name: id,
      frame: frame,
      visibleFrame: CGRect(
        x: frame.minX,
        y: frame.minY,
        width: frame.width,
        height: frame.height - visibleTopInset
      ),
      isBuiltIn: isBuiltIn,
      hasNotch: hasNotch
    )
  }
}
