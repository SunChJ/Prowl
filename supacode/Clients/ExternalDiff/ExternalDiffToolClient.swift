import ComposableArchitecture
import Foundation

nonisolated struct ExternalDiffToolClient: Sendable {
  var open:
    @MainActor @Sendable (
      _ settings: ExternalDiffSettings,
      _ worktree: Worktree,
      _ resolvedKeybindings: ResolvedKeybindingMap,
      _ onError: @escaping @MainActor @Sendable (OpenActionError) -> Void
    ) async -> Void
}

extension ExternalDiffToolClient: DependencyKey {
  static let liveValue = ExternalDiffToolClient { settings, worktree, resolvedKeybindings, onError in
    @Dependency(TerminalClient.self) var terminalClient
    @Dependency(ShellClient.self) var shellClient
    @Dependency(ExternalDiffSnapshotClient.self) var snapshotClient
    @Dependency(OutgoingChangesClient.self) var outgoingChangesClient

    switch settings.tool {
    case .builtIn:
      @Shared(.settingsFile) var settingsFile
      DiffWindowManager.shared.show(
        worktreeURL: worktree.workingDirectory,
        branchName: worktree.name,
        outgoingResolver: outgoingChangesClient.makeResolver(worktree),
        resolvedKeybindings: resolvedKeybindings,
        colorScheme: settingsFile.global.appearanceMode.colorScheme
      )

    case .hunk:
      await terminalClient.send(
        .createTabWithInput(
          worktree,
          input: "hunk diff",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Hunk Diff",
          customCommandIcon: "square.split.2x1"
        )
      )

    case .fileMerge:
      await runGUICommand(
        ExternalDiffGUICommandRequest(tool: settings.tool, executableName: "opendiff", arguments: []),
        worktree: worktree,
        shellClient: shellClient,
        snapshotClient: snapshotClient,
        onError: onError
      )

    case .kaleidoscope:
      await runGUICommand(
        ExternalDiffGUICommandRequest(tool: settings.tool, executableName: "ksdiff", arguments: ["--diff"]),
        worktree: worktree,
        shellClient: shellClient,
        snapshotClient: snapshotClient,
        onError: onError
      )

    case .custom:
      await runCustomCommand(
        settings: settings,
        worktree: worktree,
        shellClient: shellClient,
        snapshotClient: snapshotClient,
        onError: onError
      )
    }
  }

  static let testValue = ExternalDiffToolClient { _, _, _, _ in }
}

extension DependencyValues {
  var externalDiffToolClient: ExternalDiffToolClient {
    get { self[ExternalDiffToolClient.self] }
    set { self[ExternalDiffToolClient.self] = newValue }
  }
}

private struct ExternalDiffGUICommandRequest {
  let tool: ExternalDiffTool
  let executableName: String
  let arguments: [String]
}

private func runGUICommand(
  _ request: ExternalDiffGUICommandRequest,
  worktree: Worktree,
  shellClient: ShellClient,
  snapshotClient: ExternalDiffSnapshotClient,
  onError: @escaping @MainActor @Sendable (OpenActionError) -> Void
) async {
  do {
    let snapshot = try await snapshotClient.makeSnapshotPair(worktree)
    let executableURL = URL(fileURLWithPath: "/usr/bin/env")
    _ = try await shellClient.runLogin(
      executableURL,
      [request.executableName] + request.arguments + [
        snapshot.leftURL.path(percentEncoded: false),
        snapshot.rightURL.path(percentEncoded: false),
      ],
      worktree.workingDirectory
    )
  } catch {
    onError(openError(for: request.tool, error: error))
  }
}

private func runCustomCommand(
  settings: ExternalDiffSettings,
  worktree: Worktree,
  shellClient: ShellClient,
  snapshotClient: ExternalDiffSnapshotClient,
  onError: @escaping @MainActor @Sendable (OpenActionError) -> Void
) async {
  let template = settings.customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !template.isEmpty else {
    onError(
      OpenActionError(
        title: "Custom diff command is empty",
        message: "Add a custom diff command in Settings before opening the diff."
      )
    )
    return
  }
  do {
    let snapshot = try await snapshotClient.makeSnapshotPair(worktree)
    let context = ExternalDiffCommandContext(
      worktreePath: worktree.workingDirectory.path(percentEncoded: false),
      repoPath: worktree.repositoryRootURL.path(percentEncoded: false),
      branch: worktree.name,
      leftPath: snapshot.leftURL.path(percentEncoded: false),
      rightPath: snapshot.rightURL.path(percentEncoded: false)
    )
    let command = ExternalDiffCommandTemplate.render(template, context: context)
    _ = try await shellClient.runLogin(
      URL(fileURLWithPath: "/bin/zsh"),
      ["-lc", command],
      worktree.workingDirectory
    )
  } catch {
    onError(openError(for: settings.tool, error: error))
  }
}

private func openError(for tool: ExternalDiffTool, error: Error) -> OpenActionError {
  OpenActionError(
    title: "Unable to open diff in \(tool.title)",
    message: error.localizedDescription
  )
}
