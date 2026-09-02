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

    #expect(frame.midX == display.notchFrame?.midX)
    #expect(frame.maxY == display.frame.maxY)
  }

  @Test func notchFrameUsesAuxiliaryAreasAsContentExclusionZone() throws {
    let frame = CGRect(x: 0, y: 0, width: 1_512, height: 982)

    let notchFrame = AgentIslandScreenLayout.notchFrame(
      screenFrame: frame,
      safeAreaTopInset: 32,
      auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
      auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32)
    )

    #expect(try #require(notchFrame) == CGRect(x: 663, y: 950, width: 185, height: 32))
  }

  @Test func notchedCompactLayoutReservesThePhysicalCutout() {
    let layout = AgentIslandNotchLayout(cutoutSize: CGSize(width: 185, height: 32))

    #expect(layout.compactWidth == 425)
    #expect(layout.compactHeight == 32)
    #expect(layout.wingWidth == 120)
    #expect(layout.rootWidth == 425)
    #expect((layout.wingWidth * 2) + layout.cutoutSize.width == layout.compactWidth)
  }

  @Test func notchedCompactHeightFollowsTheCutoutWithAFloorForTheIconCluster() {
    // "More Space" scaling reports a shorter inset; "Larger Text" a taller one. Both stay flush.
    #expect(AgentIslandNotchLayout(cutoutSize: CGSize(width: 165, height: 27)).compactHeight == 28)
    #expect(AgentIslandNotchLayout(cutoutSize: CGSize(width: 185, height: 32)).compactHeight == 32)
    #expect(AgentIslandNotchLayout(cutoutSize: CGSize(width: 208, height: 36)).compactHeight == 36)
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

  // MARK: Settings picker selection

  @Test func displaySelectionMatchesStoredDisplayByIDOnly() {
    // `localizedName` changes with the system language; the picker must still find the tag.
    let stored = AgentIslandDisplayPreference.display(id: "uuid-1", name: "Built-in Display")
    let renamed = AgentIslandDisplayPreference.display(id: "uuid-1", name: "内建显示器")

    #expect(AgentIslandDisplaySelection(stored) == .display(id: "uuid-1"))
    #expect(AgentIslandDisplaySelection(stored) == AgentIslandDisplaySelection(renamed))
    #expect(AgentIslandDisplaySelection(.automatic) == .automatic)
  }

  @Test func displaySelectionTakesTheConnectedDisplayNameFromTheCatalog() {
    let connected = screen(id: "uuid-1", name: "内建显示器")
    let stored = AgentIslandDisplayPreference.display(id: "uuid-1", name: "Built-in Display")

    let resolved = AgentIslandDisplaySelection.display(id: "uuid-1")
      .preference(screens: [connected], current: stored)

    #expect(resolved == .display(id: "uuid-1", name: "内建显示器"))
  }

  @Test func displaySelectionKeepsTheStoredNameOfADisconnectedDisplay() {
    let stored = AgentIslandDisplayPreference.display(id: "uuid-2", name: "Studio Display")

    let resolved = AgentIslandDisplaySelection.display(id: "uuid-2")
      .preference(screens: [screen(id: "uuid-1")], current: stored)

    #expect(resolved == stored)
  }

  @Test func displaySelectionFallsBackToTheIDWhenNoNameIsKnown() {
    let resolved = AgentIslandDisplaySelection.display(id: "uuid-3")
      .preference(screens: [], current: .automatic)

    #expect(resolved == .display(id: "uuid-3", name: "uuid-3"))
  }

  @Test func automaticSelectionClearsThePinnedDisplay() {
    let stored = AgentIslandDisplayPreference.display(id: "uuid-1", name: "Studio Display")

    let resolved = AgentIslandDisplaySelection.automatic
      .preference(screens: [screen(id: "uuid-1")], current: stored)

    #expect(resolved == .automatic)
  }

  private func screen(
    id: String,
    name: String? = nil,
    origin: CGPoint = .zero,
    visibleTopInset: CGFloat = 24,
    isBuiltIn: Bool = false,
    hasNotch: Bool = false
  ) -> AgentIslandScreenDescriptor {
    let frame = CGRect(origin: origin, size: CGSize(width: 1_920, height: 1_080))
    return AgentIslandScreenDescriptor(
      id: id,
      name: name ?? id,
      frame: frame,
      visibleFrame: CGRect(
        x: frame.minX,
        y: frame.minY,
        width: frame.width,
        height: frame.height - visibleTopInset
      ),
      isBuiltIn: isBuiltIn,
      notchFrame: hasNotch
        ? CGRect(x: frame.midX - 92.5, y: frame.maxY - 32, width: 185, height: 32)
        : nil
    )
  }
}
