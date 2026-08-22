import Foundation
import Testing

@testable import supacode

@MainActor
struct CLILifecycleCommandHandlerTests {
  @Test func createPaneDirectionsMapToTerminalDirections() {
    #expect(CreatePaneDirection.right.terminalSplitDirection == .right)
    #expect(CreatePaneDirection.left.terminalSplitDirection == .left)
    #expect(CreatePaneDirection.upward.terminalSplitDirection == .top)
    #expect(CreatePaneDirection.down.terminalSplitDirection == .down)
  }

  @Test func createTabResolvesWorktreeCreatesTabAndReturnsCreatePayload() async throws {
    let base = makeTarget(tabID: "base-tab", paneID: "base-pane")
    let created = makeTarget(tabID: "created-tab", paneID: "created-pane")
    var resolvedSelector: TargetSelector?
    var createPath: String?
    let handler = LifecycleCommandHandler(
      resolveCreateTarget: { selector in
        resolvedSelector = selector
        return .success(base)
      },
      resolveCloseTarget: { _ in .success(LifecycleResolvedTarget(resource: .pane, target: base)) },
      createTab: { _, path in
        createPath = path
        return created
      },
      createPane: { _, _ in nil },
      closeTab: { _, _ in true },
      closePane: { _, _ in true }
    )

    let response = await handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .create(CreateInput(resource: .tab, selector: .worktree("App"), path: "/Projects/App"))
      )
    )

    #expect(response.ok)
    #expect(response.command == "create")
    #expect(response.schemaVersion == "prowl.cli.create.v1")
    #expect(resolvedSelector == .worktree("App"))
    #expect(createPath == "/Projects/App")
    let data = try #require(response.data)
    let payload = try data.decode(as: LifecycleCommandPayload.self)
    #expect(payload.resource == .tab)
    #expect(payload.target.tab.id == "created-tab")
  }

  @Test func createPaneUsesResolvedAnchorAndReturnsCreatePayload() async throws {
    let anchor = makeTarget(tabID: "anchor-tab", paneID: "anchor-pane")
    let created = makeTarget(tabID: "anchor-tab", paneID: "created-pane")
    var resolvedSelector: TargetSelector?
    var createdFrom: TabResolvedTarget?
    var createdDirection: CreatePaneDirection?
    let handler = LifecycleCommandHandler(
      resolveCreateTarget: { selector in
        resolvedSelector = selector
        return .success(anchor)
      },
      resolveCloseTarget: { _ in .success(LifecycleResolvedTarget(resource: .pane, target: anchor)) },
      createTab: { _, _ in nil },
      createPane: { target, direction in
        createdFrom = target
        createdDirection = direction
        return created
      },
      closeTab: { _, _ in true },
      closePane: { _, _ in true }
    )

    let response = await handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .create(
          CreateInput(resource: .pane, selector: .pane("p12"), direction: .upward)
        )
      )
    )

    #expect(response.ok)
    #expect(resolvedSelector == .pane("p12"))
    #expect(createdFrom == anchor)
    #expect(createdDirection == .upward)
    let data = try #require(response.data)
    let payload = try data.decode(as: LifecycleCommandPayload.self)
    #expect(payload.resource == .pane)
    #expect(payload.anchor?.pane.id == "anchor-pane")
    #expect(payload.direction == .upward)
    #expect(payload.target.pane.id == "created-pane")
  }

  @Test func createPaneRejectsNonPaneSocketInputBeforeResolution() async {
    let target = makeTarget()
    var didResolve = false
    var didCreate = false
    let handler = LifecycleCommandHandler(
      resolveCreateTarget: { _ in
        didResolve = true
        return .success(target)
      },
      resolveCloseTarget: { _ in .success(LifecycleResolvedTarget(resource: .pane, target: target)) },
      createTab: { _, _ in nil },
      createPane: { _, _ in
        didCreate = true
        return target
      },
      closeTab: { _, _ in true },
      closePane: { _, _ in true }
    )

    let response = await handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .create(
          CreateInput(resource: .pane, selector: .worktree("App"), direction: .right)
        )
      )
    )

    #expect(!response.ok)
    #expect(response.error?.code == CLIErrorCode.invalidArgument)
    #expect(!didResolve)
    #expect(!didCreate)
  }

  @Test func createPaneReportsCreateFailedWhenTheSplitCannotBeMade() async throws {
    let anchor = makeTarget(tabID: "anchor-tab", paneID: "anchor-pane")
    var createAttempts = 0
    let handler = LifecycleCommandHandler(
      resolveCreateTarget: { _ in .success(anchor) },
      resolveCloseTarget: { _ in .success(LifecycleResolvedTarget(resource: .pane, target: anchor)) },
      createTab: { _, _ in nil },
      createPane: { _, _ in
        createAttempts += 1
        return nil
      },
      closeTab: { _, _ in true },
      closePane: { _, _ in true }
    )

    let response = await handler.handle(
      envelope: CommandEnvelope(
        output: .json,
        command: .create(
          CreateInput(resource: .pane, selector: .pane("p12"), direction: .down)
        )
      )
    )

    #expect(!response.ok)
    #expect(response.error?.code == CLIErrorCode.createFailed)
    #expect(createAttempts == 1)
    #expect(response.data == nil)
  }

  @Test func closeUsesResolvedResourceAndReturnsClosePayload() async throws {
    let target = makeTarget(tabID: "tab-to-close", paneID: "pane-to-close")
    var closedPane: TabResolvedTarget?
    let handler = LifecycleCommandHandler(
      resolveCreateTarget: { _ in .success(target) },
      resolveCloseTarget: { selector in
        #expect(selector == .auto("p12"))
        return .success(LifecycleResolvedTarget(resource: .pane, target: target))
      },
      createTab: { _, _ in nil },
      createPane: { _, _ in nil },
      closeTab: { _, _ in false },
      closePane: { target, force in
        #expect(force)
        closedPane = target
        return true
      }
    )

    let response = await handler.handle(
      envelope: CommandEnvelope(output: .json, command: .close(CloseInput(selector: .auto("p12"), force: true)))
    )

    #expect(response.ok)
    #expect(response.command == "close")
    #expect(response.schemaVersion == "prowl.cli.close.v1")
    #expect(closedPane == target)
    let data = try #require(response.data)
    let payload = try data.decode(as: LifecycleCommandPayload.self)
    #expect(payload.resource == .pane)
    #expect(payload.target.pane.id == "pane-to-close")
  }

  private func makeTarget(
    worktreeID: String = "App:/Projects/App",
    worktreeName: String = "App",
    worktreePath: String = "/Projects/App",
    worktreeRootPath: String = "/Projects/App",
    worktreeKind: String = "git",
    tabID: String = "tab-1",
    tabTitle: String = "App 1",
    tabSelected: Bool = true,
    paneID: String = "pane-1",
    paneTitle: String = "zsh",
    paneCWD: String? = "/Projects/App",
    paneFocused: Bool = true
  ) -> TabResolvedTarget {
    TabResolvedTarget(
      worktreeID: worktreeID,
      worktreeName: worktreeName,
      worktreePath: worktreePath,
      worktreeRootPath: worktreeRootPath,
      worktreeKind: worktreeKind,
      tabID: tabID,
      tabTitle: tabTitle,
      tabSelected: tabSelected,
      paneID: paneID,
      paneTitle: paneTitle,
      paneCWD: paneCWD,
      paneFocused: paneFocused
    )
  }
}
