import Foundation
import KeyboardShortcuts

public protocol HotkeyManaging {
  func registerHotkeys(for actions: [ActionConfig], onTrigger: @escaping (ActionConfig) -> Void)
  func unregisterAll()
}

public class HotkeyManager: HotkeyManaging {

  public init() {}

  public func registerHotkeys(
    for actions: [ActionConfig], onTrigger: @escaping (ActionConfig) -> Void
  ) {
    unregisterAll()

    for action in actions where action.enabled {
      guard let shortcutDef = action.shortcut else { continue }

      // A hand-edited shortcut with out-of-range values yields nil; skipping it
      // with a warning keeps the app launching instead of trapping (finding C1).
      guard let keyboardShortcut = shortcutDef.keyboardShortcut else {
        Logger.shared.log(
          "Action '\(action.title)' has an invalid stored shortcut "
            + "(keyCode \(shortcutDef.keyCode), modifiers \(shortcutDef.modifiers)); "
            + "hotkey not registered. Re-record it in Settings > Actions.",
          level: .warning)
        continue
      }

      let name = KeyboardShortcuts.Name(action.id)
      KeyboardShortcuts.setShortcut(keyboardShortcut, for: name)

      KeyboardShortcuts.onKeyDown(for: name) {
        Logger.shared.log("Shortcut triggered for action: \(action.title)", level: .info)
        onTrigger(action)
      }
    }
  }

  public func unregisterAll() {
    // KeyboardShortcuts manages state globally, but we can clear specific ones or all if needed.
    // For dynamic reloading, re-registering overwrites existing closures.
    // But to clean up removed actions, we should ideally wipe existing user defaults keys.
    // For MVP, since we re-assign shortcuts when actions change, it handles the basic case.
    KeyboardShortcuts.removeAllHandlers()
  }
}
