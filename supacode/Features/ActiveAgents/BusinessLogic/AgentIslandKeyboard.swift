import AppKit
import Carbon

enum AgentIslandHotKeyAction: Equatable {
  case toggleIslandRoster
  case collapseIsland

  static func resolve(
    isRosterExpanded: Bool,
    hasEntries: Bool
  ) -> Self? {
    if isRosterExpanded {
      return .collapseIsland
    }
    return hasEntries ? .toggleIslandRoster : nil
  }
}

enum AgentIslandKeyboardCommand: Equatable {
  case collapse
  case move(ActiveAgentsFeature.NavigationDirection)
  case page(ActiveAgentsFeature.NavigationDirection)
  case activateSelection
  case activateVisibleEntry(Int)

  static func resolve(
    keyCode: UInt16,
    characters: String?,
    modifiers: NSEvent.ModifierFlags
  ) -> Self? {
    let significantModifiers = modifiers.intersection([.command, .shift, .option, .control])
    if significantModifiers == .command, let index = commandNumberIndex(for: keyCode) {
      return .activateVisibleEntry(index)
    }
    guard significantModifiers.isEmpty else { return nil }

    switch keyCode {
    case 53:
      return .collapse
    case 126:
      return .move(.previous)
    case 125:
      return .move(.next)
    case 123:
      return .page(.previous)
    case 124:
      return .page(.next)
    case 36, 49, 76:
      return .activateSelection
    default:
      break
    }

    switch characters?.lowercased() {
    case "k":
      return .move(.previous)
    case "j":
      return .move(.next)
    case "h":
      return .page(.previous)
    case "l":
      return .page(.next)
    default:
      return nil
    }
  }

  private static func commandNumberIndex(for keyCode: UInt16) -> Int? {
    switch keyCode {
    case 18, 83: return 0
    case 19, 84: return 1
    case 20, 85: return 2
    case 21, 86: return 3
    case 23, 87: return 4
    case 22, 88: return 5
    case 26, 89: return 6
    case 28, 91: return 7
    case 25, 92: return 8
    default: return nil
    }
  }
}

enum AgentIslandGlobalHotKeyCommand: Equatable {
  case toggleRoster
  case activateAttentionSlot(Int)

  fileprivate var identifier: UInt32 {
    switch self {
    case .toggleRoster:
      return 1
    case .activateAttentionSlot(let index):
      return UInt32(index + 2)
    }
  }

  fileprivate init?(identifier: UInt32) {
    if identifier == Self.toggleRoster.identifier {
      self = .toggleRoster
      return
    }
    let index = Int(identifier) - 2
    guard (0..<AgentIslandAttentionShortcut.slotLimit).contains(index) else { return nil }
    self = .activateAttentionSlot(index)
  }
}

enum AgentIslandAttentionShortcut {
  static let slotLimit = 9

  static func binding(at index: Int) -> Keybinding? {
    guard (0..<slotLimit).contains(index) else { return nil }
    return Keybinding(
      key: String(index + 1),
      modifiers: KeybindingModifiers(command: true, option: true)
    )
  }

  static func slotCount(
    isRosterExpanded: Bool,
    attentionEntryCount: Int
  ) -> Int {
    guard !isRosterExpanded else { return 0 }
    return min(max(0, attentionEntryCount), slotLimit)
  }
}

struct AgentIslandGlobalHotKeyConfiguration: Equatable {
  struct Changes: OptionSet, Equatable {
    let rawValue: Int

    static let toggle = Self(rawValue: 1 << 0)
    static let attentionSlots = Self(rawValue: 1 << 1)
  }

  let toggleBinding: Keybinding?
  let attentionSlotCount: Int

  init(
    toggleBinding: Keybinding?,
    isRosterExpanded: Bool,
    attentionEntryCount: Int
  ) {
    self.toggleBinding = toggleBinding
    attentionSlotCount = AgentIslandAttentionShortcut.slotCount(
      isRosterExpanded: isRosterExpanded,
      attentionEntryCount: attentionEntryCount
    )
  }

  func changes(from previous: Self?, force: Bool = false) -> Changes {
    guard !force, let previous else { return [.toggle, .attentionSlots] }
    var changes: Changes = []
    if toggleBinding != previous.toggleBinding {
      changes.insert(.toggle)
    }
    if attentionSlotCount != previous.attentionSlotCount {
      changes.insert(.attentionSlots)
    }
    return changes
  }
}

private struct AgentIslandCarbonHotKeyDescriptor {
  let keyCode: UInt32
  let modifiers: UInt32

  @MainActor
  init?(binding: Keybinding) {
    let resolver = ShortcutKeyTokenResolver()
    guard
      let keyCode = (0..<128).first(where: { candidate in
        let token = resolver.resolveKeyToken(
          keyCode: UInt16(candidate),
          charactersIgnoringModifiers: nil
        )
        return token == binding.key || token == Self.physicalDigitToken(for: binding.key)
      })
    else {
      return nil
    }

    var carbonModifiers: UInt32 = 0
    if binding.modifiers.command { carbonModifiers |= UInt32(cmdKey) }
    if binding.modifiers.shift { carbonModifiers |= UInt32(shiftKey) }
    if binding.modifiers.option { carbonModifiers |= UInt32(optionKey) }
    if binding.modifiers.control { carbonModifiers |= UInt32(controlKey) }
    guard carbonModifiers != 0 else { return nil }

    self.keyCode = UInt32(keyCode)
    self.modifiers = carbonModifiers
  }

  private static func physicalDigitToken(for key: String) -> String? {
    guard key.count == 1, key.first?.isNumber == true else { return nil }
    return "digit_\(key)"
  }
}

@MainActor
final class AgentIslandGlobalHotKeys {
  private static let signature: OSType = 0x5052_574C  // PRWL
  private static let logger = SupaLogger("AgentIsland")

  private var eventHandler: EventHandlerRef?
  private var hotKeys: [UInt32: EventHotKeyRef] = [:]
  private let action: @MainActor (AgentIslandGlobalHotKeyCommand) -> Void

  init(action: @escaping @MainActor (AgentIslandGlobalHotKeyCommand) -> Void) {
    self.action = action
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr,
          hotKeyID.signature == AgentIslandGlobalHotKeys.signature,
          let command = AgentIslandGlobalHotKeyCommand(identifier: hotKeyID.id)
        else {
          return OSStatus(eventNotHandledErr)
        }
        let registrar = Unmanaged<AgentIslandGlobalHotKeys>.fromOpaque(userData)
          .takeUnretainedValue()
        MainActor.assumeIsolated {
          registrar.action(command)
        }
        return noErr
      },
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
    if status != noErr {
      Self.logger.warning("hot_key_handler_install_failed status=\(status)")
    }
  }

  func registerToggle(binding: Keybinding?) {
    register(command: .toggleRoster, binding: binding)
  }

  func registerAttentionSlots(count: Int) {
    for index in 0..<AgentIslandAttentionShortcut.slotLimit {
      unregister(command: .activateAttentionSlot(index))
    }
    for index in 0..<min(max(0, count), AgentIslandAttentionShortcut.slotLimit) {
      register(
        command: .activateAttentionSlot(index),
        binding: AgentIslandAttentionShortcut.binding(at: index)
      )
    }
  }

  private func register(
    command: AgentIslandGlobalHotKeyCommand,
    binding: Keybinding?
  ) {
    unregister(command: command)
    guard let binding, let descriptor = AgentIslandCarbonHotKeyDescriptor(binding: binding) else {
      return
    }
    let hotKeyID = EventHotKeyID(signature: Self.signature, id: command.identifier)
    var hotKey: EventHotKeyRef?
    let status = RegisterEventHotKey(
      descriptor.keyCode,
      descriptor.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
    if status == noErr, let hotKey {
      hotKeys[command.identifier] = hotKey
    } else {
      Self.logger.warning("hot_key_registration_failed binding=\(binding.display) status=\(status)")
    }
  }

  private func unregister(command: AgentIslandGlobalHotKeyCommand) {
    if let hotKey = hotKeys.removeValue(forKey: command.identifier) {
      UnregisterEventHotKey(hotKey)
    }
  }

  func stop() {
    for hotKey in hotKeys.values {
      UnregisterEventHotKey(hotKey)
    }
    hotKeys.removeAll()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }
}
