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
  typealias CloseTabProvider = @MainActor (TabResolvedTarget, Bool) -> Bool
  typealias ClosePaneProvider = @MainActor (TabResolvedTarget, Bool) -> Bool

  private let resolveCreateTarget: ResolveCreateTargetProvider
  private let resolveCloseTarget: ResolveCloseTargetProvider
  private let createTab: CreateTabProvider
  private let closeTab: CloseTabProvider
  private let closePane: ClosePaneProvider

  init(
    resolveCreateTarget: @escaping ResolveCreateTargetProvider,
    resolveCloseTarget: @escaping ResolveCloseTargetProvider,
    createTab: @escaping CreateTabProvider,
    closeTab: @escaping CloseTabProvider,
    closePane: @escaping ClosePaneProvider
  ) {
    self.resolveCreateTarget = resolveCreateTarget
    self.resolveCloseTarget = resolveCloseTarget
    self.createTab = createTab
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
    guard input.resource == .tab else {
      return errorResponse(
        command: "create",
        code: CLIErrorCode.invalidArgument,
        message: "create pane is not available yet."
      )
    }
    guard case .worktree = input.selector else {
      return errorResponse(
        command: "create",
        code: CLIErrorCode.invalidArgument,
        message: "create tab requires a worktree target."
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

  private func success(command: String, resource: LifecycleResource, target: TabResolvedTarget) -> CommandResponse {
    do {
      return try CommandResponse(
        ok: true,
        command: command,
        schemaVersion: "prowl.cli.\(command).v1",
        data: RawJSON(encoding: LifecycleCommandPayload(resource: resource, target: makePayloadTarget(from: target)))
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

extension String {
  fileprivate func trimmingTrailingSlash() -> String {
    var value = self
    while value.count > 1, value.hasSuffix("/") {
      value.removeLast()
    }
    return value
  }
}
