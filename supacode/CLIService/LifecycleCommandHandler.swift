import Foundation

struct LifecycleResolvedTarget: Sendable, Equatable {
  let resource: LifecycleResource
  let target: TabResolvedTarget
}

@MainActor
final class LifecycleCommandHandler: CommandHandler {
  typealias ResolveCreateTargetProvider = @MainActor (TargetSelector) -> Result<TabResolvedTarget, TargetResolverError>
  typealias ResolveCloseTargetProvider =
    @MainActor (TargetSelector) -> Result<LifecycleResolvedTarget, TargetResolverError>
  typealias CreateTabProvider = @MainActor (TabResolvedTarget, String?) -> TabResolvedTarget?
  typealias CreatePaneProvider = @MainActor (TabResolvedTarget, CreatePaneDirection) -> TabResolvedTarget?
  typealias CloseTabProvider = @MainActor (TabResolvedTarget, Bool) -> Bool
  typealias ClosePaneProvider = @MainActor (TabResolvedTarget, Bool) -> Bool

  private let resolveCreateTarget: ResolveCreateTargetProvider
  private let resolveCloseTarget: ResolveCloseTargetProvider
  private let createTab: CreateTabProvider
  private let createPane: CreatePaneProvider
  private let closeTab: CloseTabProvider
  private let closePane: ClosePaneProvider

  init(
    resolveCreateTarget: @escaping ResolveCreateTargetProvider,
    resolveCloseTarget: @escaping ResolveCloseTargetProvider,
    createTab: @escaping CreateTabProvider,
    createPane: @escaping CreatePaneProvider,
    closeTab: @escaping CloseTabProvider,
    closePane: @escaping ClosePaneProvider
  ) {
    self.resolveCreateTarget = resolveCreateTarget
    self.resolveCloseTarget = resolveCloseTarget
    self.createTab = createTab
    self.createPane = createPane
    self.closeTab = closeTab
    self.closePane = closePane
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    switch envelope.command {
    case .create(let input):
      return handleCreate(input)
    case .close(let input):
      return handleClose(input)
    default:
      return errorResponse(
        command: envelope.command.name, code: CLIErrorCode.invalidArgument, message: "Invalid command.")
    }
  }

  private func handleCreate(_ input: CreateInput) -> CommandResponse {
    switch input.resource {
    case .tab:
      return handleCreateTab(input)
    case .pane:
      return handleCreatePane(input)
    }
  }

  private func handleCreateTab(_ input: CreateInput) -> CommandResponse {
    guard case .worktree = input.selector, input.direction == nil else {
      return errorResponse(
        command: "create",
        code: CLIErrorCode.invalidArgument,
        message: "create tab requires a worktree target and does not accept a direction."
      )
    }

    let target: TabResolvedTarget
    switch resolveCreateTarget(input.selector) {
    case .success(let resolved):
      target = resolved
    case .failure(let error):
      return mapResolverError(command: "create", error: error)
    }

    let path = normalizedAllowedPath(input.path, worktreePath: target.worktreePath)
    guard input.path == nil || path != nil else {
      return errorResponse(
        command: "create",
        code: CLIErrorCode.pathNotAllowed,
        message: "Tab path must be inside the resolved worktree."
      )
    }
    guard let createdTarget = createTab(target, path) else {
      return errorResponse(command: "create", code: CLIErrorCode.createFailed, message: "Failed to create tab.")
    }
    return success(command: "create", resource: .tab, target: createdTarget)
  }

  private func handleCreatePane(_ input: CreateInput) -> CommandResponse {
    guard case .pane = input.selector, input.path == nil, let direction = input.direction else {
      return errorResponse(
        command: "create",
        code: CLIErrorCode.invalidArgument,
        message: "create pane requires a pane target and an explicit direction."
      )
    }

    let anchor: TabResolvedTarget
    switch resolveCreateTarget(input.selector) {
    case .success(let resolved):
      anchor = resolved
    case .failure(let error):
      return mapResolverError(command: "create", error: error)
    }

    guard let createdTarget = createPane(anchor, direction) else {
      return errorResponse(command: "create", code: CLIErrorCode.createFailed, message: "Failed to create pane.")
    }
    return success(
      command: "create",
      resource: .pane,
      target: createdTarget,
      anchor: anchor,
      direction: direction
    )
  }

  private func handleClose(_ input: CloseInput) -> CommandResponse {
    guard !input.selector.isNone else {
      return errorResponse(
        command: "close",
        code: CLIErrorCode.invalidArgument,
        message: "close requires an explicit pane or tab target."
      )
    }

    let resolved: LifecycleResolvedTarget
    switch resolveCloseTarget(input.selector) {
    case .success(let target):
      resolved = target
    case .failure(let error):
      return mapResolverError(command: "close", error: error)
    }

    let didClose =
      switch resolved.resource {
      case .tab:
        closeTab(resolved.target, input.force)
      case .pane:
        closePane(resolved.target, input.force)
      }
    guard didClose else {
      return errorResponse(
        command: "close",
        code: CLIErrorCode.closeFailed,
        message: "Failed to close \(resolved.resource.rawValue)."
      )
    }
    return success(command: "close", resource: resolved.resource, target: resolved.target)
  }

  private func normalizedAllowedPath(_ path: String?, worktreePath: String) -> String? {
    guard let path else { return nil }
    let normalizedPath = normalize(path)
    let normalizedWorktree = normalize(worktreePath)
    guard normalizedPath == normalizedWorktree || normalizedPath.hasPrefix(normalizedWorktree + "/") else {
      return nil
    }
    return normalizedPath
  }

  private func normalize(_ path: String) -> String {
    URL(fileURLWithPath: path, isDirectory: true)
      .standardizedFileURL
      .path(percentEncoded: false)
      .trimmingTrailingSlash()
  }

  private func success(
    command: String,
    resource: LifecycleResource,
    target: TabResolvedTarget,
    anchor: TabResolvedTarget? = nil,
    direction: CreatePaneDirection? = nil
  ) -> CommandResponse {
    do {
      return try CommandResponse(
        ok: true,
        command: command,
        schemaVersion: "prowl.cli.\(command).v1",
        data: RawJSON(
          encoding: LifecycleCommandPayload(
            resource: resource,
            anchor: anchor.map { makePayloadTarget(from: $0) },
            direction: direction,
            target: makePayloadTarget(from: target)
          )
        )
      )
    } catch {
      return errorResponse(command: command, code: CLIErrorCode.createFailed, message: "Failed to encode response.")
    }
  }

  private func makePayloadTarget(from target: TabResolvedTarget) -> TabTarget {
    TabTarget(
      worktree: TabTargetWorktree(
        id: target.worktreeID,
        name: target.worktreeName,
        path: target.worktreePath,
        rootPath: target.worktreeRootPath,
        kind: target.worktreeKind
      ),
      tab: TabTargetTab(
        id: target.tabID,
        title: target.tabTitle,
        selected: target.tabSelected
      ),
      pane: TabTargetPane(
        id: target.paneID,
        title: target.paneTitle,
        cwd: target.paneCWD,
        focused: target.paneFocused
      )
    )
  }

  private func mapResolverError(command: String, error: TargetResolverError) -> CommandResponse {
    switch error {
    case .notFound(let message):
      errorResponse(command: command, code: CLIErrorCode.targetNotFound, message: message)
    case .notUnique(let message):
      errorResponse(command: command, code: CLIErrorCode.targetNotUnique, message: message)
    }
  }

  private func errorResponse(command: String, code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: command,
      schemaVersion: "prowl.cli.\(command).v1",
      error: CommandError(code: code, message: message)
    )
  }
}

extension CreatePaneDirection {
  var terminalSplitDirection: UserCustomSplitDirection {
    switch self {
    case .right: .right
    case .left: .left
    case .upward: .top
    case .down: .down
    }
  }
}

extension String {
  fileprivate func trimmingTrailingSlash() -> String {
    var value = self
    while value.count > 1, value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }
}
