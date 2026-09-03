import AppKit
import Carbon

enum AgentIslandHotKeyAction: Equatable {
  case toggleSidebarPanel
  case toggleIslandRoster
  case collapseIsland

  static func resolve(
    appIsActive: Bool,
    isRosterExpanded: Bool,
    hasEntries: Bool
  ) -> Self? {
    if isRosterExpanded {
      return .collapseIsland
    }
    if appIsActive {
      return .toggleSidebarPanel
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
    case "u":
      return .page(.previous)
    case "d":
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
final class AgentIslandGlobalHotKey {
  private static let signature: OSType = 0x5052_574C  // PRWL
  private static let identifier: UInt32 = 1
  private static let logger = SupaLogger("AgentIsland")

  private var eventHandler: EventHandlerRef?
  private var hotKey: EventHotKeyRef?
  private let action: @MainActor () -> Void

  init(action: @escaping @MainActor () -> Void) {
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
          hotKeyID.signature == AgentIslandGlobalHotKey.signature,
          hotKeyID.id == AgentIslandGlobalHotKey.identifier
        else {
          return OSStatus(eventNotHandledErr)
        }
        let registrar = Unmanaged<AgentIslandGlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated {
          registrar.action()
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

  func register(binding: Keybinding?) {
    unregister()
    guard let binding, let descriptor = AgentIslandCarbonHotKeyDescriptor(binding: binding) else {
      return
    }
    let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
    let status = RegisterEventHotKey(
      descriptor.keyCode,
      descriptor.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
    if status != noErr {
      hotKey = nil
      Self.logger.warning("hot_key_registration_failed binding=\(binding.display) status=\(status)")
    }
  }

  func unregister() {
    if let hotKey {
      UnregisterEventHotKey(hotKey)
      self.hotKey = nil
    }
  }

  func stop() {
    unregister()
    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }
}
