import Cocoa

public class PermissionManager {
    private static let promptedKey = "overtype-has-prompted-accessibility"
    
    @discardableResult
    public static func checkAndPrompt() -> Bool {
        // 1. Check silently first
        let isTrusted = AXIsProcessTrusted()
        
        if isTrusted {
            return true
        }
        
        Logger.shared.log("Accessibility permissions not granted.", level: .warning)
        
        let hasPrompted = UserDefaults.standard.bool(forKey: promptedKey)
        if !hasPrompted {
            // First launch: Trigger native macOS prompt only (no custom instructions dialog)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            UserDefaults.standard.set(true, forKey: promptedKey)
        } else {
            // Subsequent launches: Show custom instructions dialog since native prompt won't show again
            showPermissionInstructions()
        }
        
        return false
    }
    
    private static func showPermissionInstructions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Overtype requires Accessibility permissions to read and replace text in other applications.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            } else {
                NSApp.terminate(nil)
            }
        }
    }
}
