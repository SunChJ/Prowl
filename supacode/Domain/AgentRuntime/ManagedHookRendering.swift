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

/// JSON settings hook merging shared by every runtime whose hook configuration is a settings
/// object: Claude (`--settings`, last-wins, inline or path), Qoder (`--settings`, first-wins,
/// inline or path), and Droid (`--settings`, last-wins, path only).
nonisolated enum ManagedHookSettings {
  static let maximumBytes = 256 * 1_024

  /// Decode an inline-JSON-or-path settings source into an object, or fail closed.
  static func object(
    from source: String,
    launchDirectory: URL,
    readFile: (URL, Int) -> ClaudeSettingsReadResult
  ) -> [String: Any]? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    let data: Data
    if trimmed.hasPrefix("{") {
      data = Data(trimmed.utf8)
      guard data.count <= maximumBytes else { return nil }
    } else {
      let sourceURL = URL(filePath: source, relativeTo: launchDirectory).standardizedFileURL
      switch readFile(sourceURL, maximumBytes) {
      case .stable(let value): data = value
      case .changed, .oversized, .unreadable: return nil
      }
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  /// Append Prowl's command hooks while preserving unknown fields and every existing handler.
  /// Returns `nil` when the object's `hooks` shape is not one this merge understands.
  static func merged(_ object: [String: Any], hookCommands: [String: String]) -> [String: Any]? {
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
        matchers.append(["hooks": [["command": command, "type": "command"]]])
      }
      hooks[event] = matchers
    }
    object["hooks"] = hooks
    return object
  }

  static func serializedData(_ object: [String: Any]) -> Data? {
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
      ),
      data.count <= maximumBytes
    else { return nil }
    return data
  }

  static func serialized(_ object: [String: Any]) -> String? {
    serializedData(object).flatMap { String(data: $0, encoding: .utf8) }
  }

  /// Managed options are inserted before the runtime's prompt argument and before any
  /// end-of-options sentinel, so they are always parsed as options.
  static func insertionIndex(promptArgumentIndex: Int?, arguments: [String]) -> Int {
    let promptIndex =
      promptArgumentIndex.flatMap { arguments.indices.contains($0) ? $0 : nil } ?? arguments.endIndex
    let sentinelIndex = arguments.firstIndex(of: "--") ?? arguments.endIndex
    return min(promptIndex, sentinelIndex)
  }

  static func degraded(
    _ invocation: AgentInvocation,
    runtime: AgentNativeHookRuntime,
    message: String
  ) -> AgentHookPreparationOutcome {
    AgentHookPreparationOutcome(
      originalInvocation: invocation,
      prepared: nil,
      warning: LifecycleCommandWarning(
        code: .managedHookDegraded,
        runtime: runtime.rawValue,
        message: message
      )
    )
  }

  private static func containsCommand(_ command: String, in matchers: [[String: Any]]) -> Bool {
    matchers.contains { matcher in
      guard let handlers = matcher["hooks"] as? [[String: Any]] else { return false }
      return handlers.contains {
        ($0["type"] as? String) == "command" && ($0["command"] as? String) == command
      }
    }
  }
}

nonisolated extension ManagedHookSettings {
  /// Which repeated occurrence of a settings option the runtime actually honors.
  enum Precedence: Sendable {
    case firstWins
    case lastWins
  }

  enum SettingsScan: Equatable {
    case none
    case source(String)
    case malformed
  }

  /// Find the settings source the runtime will honor. `--option value` and `--option=value`
  /// are both recognized; the prompt argument is skipped so it can never be read as a value.
  static func scanSettings(
    arguments: [String],
    optionName: String,
    precedence: Precedence,
    promptArgumentIndex: Int?
  ) -> SettingsScan {
    let joinedPrefix = "\(optionName)="
    var found: String?
    var index = 0
    while index < arguments.count {
      if index == promptArgumentIndex {
        index += 1
        continue
      }
      let argument = arguments[index]
      if argument == "--" { break }
      if argument == optionName {
        guard arguments.indices.contains(index + 1), index + 1 != promptArgumentIndex else {
          return .malformed
        }
        if found == nil || precedence == .lastWins { found = arguments[index + 1] }
        index += 2
        continue
      }
      if argument.hasPrefix(joinedPrefix) {
        let value = String(argument.dropFirst(joinedPrefix.count))
        if found == nil || precedence == .lastWins { found = value }
      }
      index += 1
    }
    return found.map(SettingsScan.source) ?? .none
  }

  enum EffectiveSettings {
    /// The object the runtime would load: empty when the user supplied no source.
    case object([String: Any])
    /// A source exists but cannot be used. Injecting anyway would drop the user's config,
    /// so the launch must degrade instead.
    case unusable
  }

  /// Every settings-based runtime uses the same option name; only precedence differs.
  static let settingsOptionName = "--settings"

  static func effectiveObject(
    arguments: [String],
    precedence: Precedence,
    promptArgumentIndex: Int?,
    launchDirectory: URL,
    readFile: (URL, Int) -> ClaudeSettingsReadResult
  ) -> EffectiveSettings {
    switch scanSettings(
      arguments: arguments,
      optionName: settingsOptionName,
      precedence: precedence,
      promptArgumentIndex: promptArgumentIndex
    ) {
    case .none:
      return .object([:])
    case .malformed:
      return .unusable
    case .source(let value):
      guard let object = object(from: value, launchDirectory: launchDirectory, readFile: readFile)
      else { return .unusable }
      return .object(object)
    }
  }
}

/// Copilot loads every `--plugin-dir` additively, so Prowl appends its own bundled plugin and
/// never merges with, replaces, or inspects the user's plugins or `~/.copilot/hooks/*.json`.
nonisolated enum CopilotHookPluginRenderer {
  /// Copilot passes a prompted start as the value of `--interactive` / `--prompt`, so managed
  /// options must land before that option rather than between the option and its value.
  static func prepare(
    invocation: AgentInvocation,
    pluginDirectory: URL,
    promptArgumentIndex: Int?
  ) -> AgentHookPreparedInvocation {
    var arguments = invocation.arguments
    let insertionIndex = ManagedHookSettings.insertionIndex(
      promptArgumentIndex: promptArgumentIndex.map { max(0, $0 - 1) },
      arguments: arguments
    )
    arguments.insert(contentsOf: ["--plugin-dir", ""], at: insertionIndex)
    return AgentHookPreparedInvocation(
      invocation: AgentInvocation(executable: invocation.executable, arguments: arguments),
      argumentValues: [insertionIndex + 1: pluginDirectory.path(percentEncoded: false)]
    )
  }
}

/// Qoder honors the *first* `--settings`, so a merged object is inserted ahead of the user's.
/// Inserting after would leave Prowl's hooks dead; inserting an unmerged object ahead would
/// silently disable the user's settings.
nonisolated enum QoderHookSettingsPreparer {
  static func prepare(
    invocation: AgentInvocation,
    launchDirectory: URL,
    promptArgumentIndex: Int?,
    hookCommands: [String: String],
    readFile: (URL, Int) -> ClaudeSettingsReadResult
  ) -> AgentHookPreparationOutcome {
    // `--setting-sources` drops flag-supplied hooks entirely, so injecting would only create
    // a channel that never fires.
    if containsSettingSources(invocation.arguments, promptArgumentIndex: promptArgumentIndex) {
      return ManagedHookSettings.degraded(
        invocation,
        runtime: .qoder,
        message: "Managed Qoder hooks are unavailable when --setting-sources is set; launching unchanged."
      )
    }

    guard
      case .object(let base) = ManagedHookSettings.effectiveObject(
        arguments: invocation.arguments,
        precedence: .firstWins,
        promptArgumentIndex: promptArgumentIndex,
        launchDirectory: launchDirectory,
        readFile: readFile
      ),
      let merged = ManagedHookSettings.merged(base, hookCommands: hookCommands),
      let json = ManagedHookSettings.serialized(merged)
    else {
      return ManagedHookSettings.degraded(
        invocation,
        runtime: .qoder,
        message: "Managed Qoder hooks could not be prepared; launching with the original settings."
      )
    }

    var arguments = invocation.arguments
    arguments.insert(contentsOf: ["--settings", ""], at: 0)
    return AgentHookPreparationOutcome(
      originalInvocation: invocation,
      prepared: AgentHookPreparedInvocation(
        invocation: AgentInvocation(executable: invocation.executable, arguments: arguments),
        argumentValues: [1: json]
      ),
      warning: nil
    )
  }

  private static func containsSettingSources(
    _ arguments: [String],
    promptArgumentIndex: Int?
  ) -> Bool {
    for (index, argument) in arguments.enumerated() {
      if index == promptArgumentIndex { continue }
      if argument == "--" { return false }
      if argument == "--setting-sources" || argument.hasPrefix("--setting-sources=") { return true }
    }
    return false
  }
}

/// Droid's `--settings` accepts a path only, so the merged object must be written to an
/// owner-only file: a user's settings can carry secrets such as `customModels[].apiKey`.
/// Repeated flags are last-wins, so Prowl's path is appended after the user's.
nonisolated enum DroidHookSettingsPreparer {
  struct MergedSettings: Equatable, Sendable {
    let data: Data?
    let warning: LifecycleCommandWarning?
  }

  /// Phase 1, pure: resolve the effective user settings and merge Prowl's handlers in.
  /// Writing is the caller's job because the owner-only store is main-actor isolated.
  static func mergedSettings(
    invocation: AgentInvocation,
    launchDirectory: URL,
    promptArgumentIndex: Int?,
    hookCommands: [String: String],
    readFile: (URL, Int) -> ClaudeSettingsReadResult
  ) -> MergedSettings {
    guard
      case .object(let base) = ManagedHookSettings.effectiveObject(
        arguments: invocation.arguments,
        precedence: .lastWins,
        promptArgumentIndex: promptArgumentIndex,
        launchDirectory: launchDirectory,
        readFile: readFile
      ),
      let merged = ManagedHookSettings.merged(base, hookCommands: hookCommands),
      let data = ManagedHookSettings.serializedData(merged)
    else {
      return MergedSettings(
        data: nil,
        warning: LifecycleCommandWarning(
          code: .managedHookDegraded,
          runtime: AgentNativeHookRuntime.droid.rawValue,
          message: "Managed Droid hooks could not be prepared; launching with the original settings."
        )
      )
    }
    return MergedSettings(data: data, warning: nil)
  }

  /// Phase 2: point Droid at the written file. Repeated flags are last-wins, so Prowl's path
  /// is appended after any the user supplied.
  static func applying(
    settingsPath: URL,
    invocation: AgentInvocation,
    promptArgumentIndex: Int?
  ) -> AgentHookPreparedInvocation {
    var arguments = invocation.arguments
    let insertionIndex = ManagedHookSettings.insertionIndex(
      promptArgumentIndex: promptArgumentIndex,
      arguments: arguments
    )
    arguments.insert(contentsOf: ["--settings", ""], at: insertionIndex)
    return AgentHookPreparedInvocation(
      invocation: AgentInvocation(executable: invocation.executable, arguments: arguments),
      argumentValues: [insertionIndex + 1: settingsPath.path(percentEncoded: false)]
    )
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
