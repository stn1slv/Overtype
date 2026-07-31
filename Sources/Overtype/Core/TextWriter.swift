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
        
        let chunkSize = settings.typingChunkSize ?? 20
        let baseDelayUs = settings.typingDelayMicroseconds ?? 2000
        let delayUs = Int(Double(baseDelayUs) / settings.typingSpeedMultiplier)
        
        Logger.shared.log("Effective typing config - deliveryMethod: chunked, chunkSize: \(chunkSize), delayUS: \(delayUs)", level: .info)
        
        let utf16Chars = Array(text.utf16)
        let totalChars = utf16Chars.count
        var chunkCount = 0
        let startTime = Date()
        
        for i in stride(from: 0, to: totalChars, by: chunkSize) {
            chunkCount += 1
            let end = min(i + chunkSize, totalChars)
            let chunkLength = end - i
            var chunk = Array(utf16Chars[i..<end])
            
            guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            
            eventDown.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: &chunk)
            eventUp.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: &chunk)
            
            eventDown.post(tap: .cghidEventTap)
            eventUp.post(tap: .cghidEventTap)
            
            if delayUs > 0 {
                usleep(useconds_t(delayUs))
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let elapsedMs = elapsed * 1000.0
        let avgPerChunk = chunkCount > 0 ? elapsedMs / Double(chunkCount) : 0
        
        Logger.shared.log(String(format: "Typing performance - chars: %d, chunks: %d, elapsed: %.1fms, avg/chunk: %.2fms", totalChars, chunkCount, elapsedMs, avgPerChunk), level: .info)
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
