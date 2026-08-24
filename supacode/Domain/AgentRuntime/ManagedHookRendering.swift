import Foundation

nonisolated enum ClaudeSettingsReadResult: Equatable, Sendable {
  case stable(Data)
  case changed
  case oversized
  case unreadable
}

nonisolated enum ClaudeSettingsStableReader {
  static func read(
    _ url: URL,
    maximumBytes: Int,
    afterRead: () -> Void = {}
  ) -> ClaudeSettingsReadResult {
    switch StableOwnerFileReader.read(url, maximumBytes: maximumBytes, afterRead: afterRead) {
    case .stable(let data): .stable(data)
    case .changed: .changed
    case .oversized: .oversized
    case .unreadable: .unreadable
    }
  }
}

nonisolated struct AgentHookPreparedInvocation: Equatable, Sendable {
  let invocation: AgentInvocation
  /// Actual argv values carried through owner-controlled surface environment.
  /// Keys are indexes in `invocation.arguments`.
  let argumentValues: [Int: String]
}

nonisolated struct AgentHookPreparationOutcome: Equatable, Sendable {
  let originalInvocation: AgentInvocation
  let prepared: AgentHookPreparedInvocation?
  let warning: LifecycleCommandWarning?
}

nonisolated enum ClaudeHookSettingsPreparer {
  static let maximumSettingsBytes = 256 * 1_024

  static func prepare(
    invocation: AgentInvocation,
    launchDirectory: URL,
    promptArgumentIndex: Int? = nil,
    hookCommands: [String: String],
    readFile: (URL, Int) -> ClaudeSettingsReadResult
  ) -> AgentHookPreparationOutcome {
    let source: SettingsSource?
    switch finalSettingsSource(
      in: invocation.arguments,
      promptArgumentIndex: promptArgumentIndex
    ) {
    case .none:
      source = nil
    case .source(let value):
      source = value
    case .malformed:
      return degraded(invocation)
    }
    let baseObject: [String: Any]
    if let source {
      switch settingsObject(
        source.value,
        launchDirectory: launchDirectory,
        readFile: readFile
      ) {
      case .success(let object):
        baseObject = object
      case .failure:
        return degraded(invocation)
      }
    } else {
      baseObject = [:]
    }

    guard let merged = mergedObject(baseObject, hookCommands: hookCommands),
      JSONSerialization.isValidJSONObject(merged),
      let data = try? JSONSerialization.data(
        withJSONObject: merged,
        options: [.sortedKeys, .withoutEscapingSlashes]
      ),
      data.count <= maximumSettingsBytes,
      let json = String(data: data, encoding: .utf8)
    else {
      return degraded(invocation)
    }

    var arguments = invocation.arguments
    let carrierIndex: Int
    if let source {
      switch source.form {
      case .separate:
        carrierIndex = source.argumentIndex
      case .joined:
        arguments[source.argumentIndex] = "--settings"
        arguments.insert("{}", at: source.argumentIndex + 1)
        carrierIndex = source.argumentIndex + 1
      }
    } else {
      let insertionIndex = managedOptionInsertionIndex(
        promptArgumentIndex: promptArgumentIndex,
        arguments: arguments
      )
      arguments.insert(contentsOf: ["--settings", "{}"], at: insertionIndex)
      carrierIndex = insertionIndex + 1
    }

    return AgentHookPreparationOutcome(
      originalInvocation: invocation,
      prepared: AgentHookPreparedInvocation(
        invocation: AgentInvocation(executable: invocation.executable, arguments: arguments),
        argumentValues: [carrierIndex: json]
      ),
      warning: nil
    )
  }

  private enum SettingsForm {
    case separate
    case joined
  }

  private enum SettingsScan {
    case none
    case source(SettingsSource)
    case malformed
  }

  private struct SettingsSource {
    let form: SettingsForm
    let argumentIndex: Int
    let value: String
  }

  private enum SettingsObjectResult {
    case success([String: Any])
    case failure
  }

  private static func finalSettingsSource(
    in arguments: [String],
    promptArgumentIndex: Int?
  ) -> SettingsScan {
    var result: SettingsSource?
    var index = 0
    while index < arguments.count {
      if index == promptArgumentIndex {
        index += 1
        continue
      }
      let argument = arguments[index]
      if argument == "--" { break }
      if argument == "--settings" {
        guard arguments.indices.contains(index + 1), index + 1 != promptArgumentIndex else {
          return .malformed
        }
        result = SettingsSource(form: .separate, argumentIndex: index + 1, value: arguments[index + 1])
        index += 2
        continue
      }
      if argument.hasPrefix("--settings=") {
        result = SettingsSource(
          form: .joined,
          argumentIndex: index,
          value: String(argument.dropFirst("--settings=".count))
        )
      }
      index += 1
    }
    return result.map(SettingsScan.source) ?? .none
  }

  private static func settingsObject(
    _ source: String,
    launchDirectory: URL,
    readFile: (URL, Int) -> ClaudeSettingsReadResult
  ) -> SettingsObjectResult {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let data: Data
    if trimmed.hasPrefix("{") {
      data = Data(trimmed.utf8)
      guard data.count <= maximumSettingsBytes else { return .failure }
    } else {
      let sourceURL = URL(filePath: source, relativeTo: launchDirectory).standardizedFileURL
      switch readFile(sourceURL, maximumSettingsBytes) {
      case .stable(let value): data = value
      case .changed, .oversized, .unreadable: return .failure
      }
    }
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return .failure
    }
    return .success(object)
  }

  private static func mergedObject(
    _ object: [String: Any],
    hookCommands: [String: String]
  ) -> [String: Any]? {
    var object = object
    var hooks: [String: Any]
    if let existing = object["hooks"] {
      guard let existing = existing as? [String: Any] else { return nil }
      hooks = existing
    } else {
      hooks = [:]
    }

    for event in hookCommands.keys.sorted() {
      guard let command = hookCommands[event] else { continue }
      var matchers: [[String: Any]]
      if let existing = hooks[event] {
        guard let existing = existing as? [[String: Any]] else { return nil }
        matchers = existing
      } else {
        matchers = []
      }
      if !containsCommand(command, in: matchers) {
        matchers.append([
          "hooks": [
            [
              "command": command,
              "type": "command",
            ]
          ]
        ])
      }
      hooks[event] = matchers
    }
    object["hooks"] = hooks
    return object
  }

  private static func containsCommand(_ command: String, in matchers: [[String: Any]]) -> Bool {
    matchers.contains { matcher in
      guard let handlers = matcher["hooks"] as? [[String: Any]] else { return false }
      return handlers.contains {
        ($0["type"] as? String) == "command" && ($0["command"] as? String) == command
      }
    }
  }

  private static func managedOptionInsertionIndex(
    promptArgumentIndex: Int?,
    arguments: [String]
  ) -> Int {
    let promptIndex =
      promptArgumentIndex.flatMap {
        arguments.indices.contains($0) ? $0 : nil
      } ?? arguments.endIndex
    let sentinelIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
    return min(promptIndex, sentinelIndex)
  }

  private static func degraded(_ invocation: AgentInvocation) -> AgentHookPreparationOutcome {
    AgentHookPreparationOutcome(
      originalInvocation: invocation,
      prepared: nil,
      warning: LifecycleCommandWarning(
        code: .managedHookDegraded,
        runtime: AgentNativeHookRuntime.claude.rawValue,
        message: "Managed Claude hooks could not be prepared; launching with the original settings."
      )
    )
  }
}

nonisolated enum CodexManagedNotifyRenderer {
  static func prepare(
    invocation: AgentInvocation,
    bundledCLIPath: String,
    promptArgumentIndex: Int? = nil
  ) -> AgentHookPreparedInvocation {
    let notifyArgv = [
      bundledCLIPath,
      "agents",
      "_hook",
      AgentNativeHookRuntime.codex.rawValue,
      "agent-turn-complete",
    ]
    let notifyData = try? JSONSerialization.data(
      withJSONObject: notifyArgv,
      options: [.withoutEscapingSlashes]
    )
    let notifyJSON = notifyData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    var arguments = invocation.arguments
    let promptIndex =
      promptArgumentIndex.flatMap {
        arguments.indices.contains($0) ? $0 : nil
      } ?? arguments.endIndex
    let sentinelIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
    let insertionIndex = min(promptIndex, sentinelIndex)
    arguments.insert(contentsOf: ["-c", "notify=[]"], at: insertionIndex)
    return AgentHookPreparedInvocation(
      invocation: AgentInvocation(executable: invocation.executable, arguments: arguments),
      argumentValues: [insertionIndex + 1: "notify=\(notifyJSON)"]
    )
  }
}
