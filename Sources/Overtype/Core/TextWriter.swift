import Cocoa
import ApplicationServices

public protocol TextWriting {
    func replaceSelection(_ selection: Selection,
                          with text: String,
                          strategy: WriteStrategy,
                          settings: GeneralConfig,
                          validateContext: () throws -> Void) throws
}

public class TextWriter: TextWriting {

    public init() {}

    public func replaceSelection(_ selection: Selection,
                                 with text: String,
                                 strategy: WriteStrategy,
                                 settings: GeneralConfig,
                                 validateContext: () throws -> Void) throws {

        switch strategy {
        case .typing:
            try writeViaCGEvent(text: text, settings: settings, validateContext: validateContext)
        }
    }

    private func writeViaCGEvent(text: String, settings: GeneralConfig, validateContext: () throws -> Void) throws {
        // According to our research, we must clear modifier keys before typing synthetic events
        // so we don't accidentally send Cmd+A instead of 'a'.

        // Wait for the user to physically release modifiers (Cmd, Option, Control, Shift)
        let maxWaitAttempts = 12
        let waitIntervalMs = 150

        for attempt in 0..<maxWaitAttempts {
            // Allow Escape / context-switch cancellation to interrupt the wait.
            try Task.checkCancellation()

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

        // Non-destructive guard (Principle II): the target context (frontmost app,
        // focused element, and live selection) may have changed during the modifier
        // wait above. Re-validate immediately before the first destructive keystroke,
        // so the delete+type never lands in a different app/element than the one read.
        try validateContext()

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

        // Note: once the selection has been deleted above, we intentionally do NOT
        // abort mid-typing on cancellation. Stopping here would leave a half-written
        // replacement in the document, which is worse than finishing. The cancellable
        // interception points are the modifier-release wait and the pre-write
        // re-validation, both before the first destructive keystroke.
        for range in Self.chunkRanges(for: utf16Chars, chunkSize: chunkSize) {
            chunkCount += 1
            let chunkLength = range.count
            var chunk = Array(utf16Chars[range])

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
    
    /// Splits a UTF-16 buffer into chunks of at most `chunkSize` units without ever
    /// splitting a surrogate pair across a boundary. A non-BMP character (emoji, some
    /// CJK) is encoded as a high+low surrogate pair; delivering an unpaired surrogate
    /// to `keyboardSetUnicodeString` produces a broken/replacement character. Pure
    /// logic, unit-tested.
    static func chunkRanges(for utf16: [UInt16], chunkSize: Int) -> [Range<Int>] {
        let total = utf16.count
        guard total > 0 else { return [] }
        guard chunkSize > 0 else { return [0..<total] }

        var ranges: [Range<Int>] = []
        var i = 0
        while i < total {
            var end = min(i + chunkSize, total)
            // If the chunk would end on a high surrogate that has a following low
            // surrogate, extend by one so the pair stays together.
            if end < total {
                let last = utf16[end - 1]
                let isHighSurrogate = (0xD800...0xDBFF).contains(last)
                if isHighSurrogate {
                    end += 1
                }
            }
            ranges.append(i..<end)
            i = end
        }
        return ranges
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
