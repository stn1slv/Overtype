import Cocoa

public class PermissionManager {
    @discardableResult
    public static func checkAndPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !isTrusted {
            Logger.shared.log("Accessibility permissions not granted. System prompt should appear.", level: .warning)
        }
        
        return isTrusted
    }
}
