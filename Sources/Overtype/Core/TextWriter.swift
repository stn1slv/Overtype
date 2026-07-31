import Cocoa
import ApplicationServices

public protocol TextWriting {
    func replaceSelection(_ selection: Selection,
                          with text: String,
                          strategy: WriteStrategy,
                          settings: GeneralConfig) throws
}

public class TextWriter: TextWriting {
    
    public init() {}
    
    public func replaceSelection(_ selection: Selection,
                                 with text: String,
                                 strategy: WriteStrategy,
                                 settings: GeneralConfig) throws {
        
        switch strategy {
        case .typing:
            try writeViaCGEvent(text: text, settings: settings)
        }
    }
    
    private func writeViaCGEvent(text: String, settings: GeneralConfig) throws {
        // According to our research, we must clear modifier keys before typing synthetic events
        // so we don't accidentally send Cmd+A instead of 'a'.
        
        // Wait for the user to physically release modifiers (Cmd, Option, Control, Shift)
        let maxWaitAttempts = 12
        let waitIntervalMs = 150
        
        for attempt in 0..<maxWaitAttempts {
            let currentFlags = CGEventSource.flagsState(.hidSystemState)
            let isHoldingModifiers = currentFlags.contains(.maskCommand) ||
                                     currentFlags.contains(.maskAlternate) ||
                                     currentFlags.contains(.maskControl)
            
            if !isHoldingModifiers {
                break
            }
            
            if attempt == maxWaitAttempts - 1 {
                Logger.shared.log("Modifiers were held too long. Aborting write to prevent unexpected hotkeys.", level: .error)
                throw AXError.cannotWriteSelectedText
            }
            
            Thread.sleep(forTimeInterval: Double(waitIntervalMs) / 1000.0)
        }
        
        guard let source = CGEventSource(stateID: .privateState) else {
            throw AXError.cannotWriteSelectedText
        }
        
        // Delete the current selection. We assume the text is currently selected.
        // We press backspace to ensure the text is cleared natively before typing.
        let backspaceKey: CGKeyCode = 51
        postKey(keyCode: backspaceKey, source: source)
        
        // Let the UI catch up
        Thread.sleep(forTimeInterval: 0.05)
        
        // Type the replacement text by inserting it into the focused element directly
        // via Accessibility where possible, as CGEvent char-by-char is slow for long text.
        // Wait, the BUILD_SPEC explicitly says: "Writing text: Use CGEvent(keyboardEventSource:virtualKey:keyDown:)"
        // But for strings, CGEvent(keyboardEventSource:source, virtualKey:0, keyDown:true) + keyboardSetUnicodeString
        
        let utf16Chars = Array(text.utf16)
        
        for char in utf16Chars {
            var uniChar = char
            guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            
            eventDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
            eventUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
            
            eventDown.post(tap: .cghidEventTap)
            eventUp.post(tap: .cghidEventTap)
            
            let delay = Double(settings.typingDelayMs) / 1000.0 / settings.typingSpeedMultiplier
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
        
        Logger.shared.log("Successfully wrote \(text.count) characters.", level: .info)
    }
    
    private func postKey(keyCode: CGKeyCode, source: CGEventSource) {
        let eventDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let eventUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        
        eventDown?.flags = []
        eventUp?.flags = []
        
        eventDown?.post(tap: .cghidEventTap)
        eventUp?.post(tap: .cghidEventTap)
    }
}
