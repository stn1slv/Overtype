import Cocoa
import ApplicationServices

public enum AXError: Error, LocalizedError {
    case cannotCreateSystemWideElement
    case noFocusedApplication
    case noFocusedElement
    case cannotReadSelectedText
    case cannotWriteSelectedText
    
    public var errorDescription: String? {
        switch self {
        case .cannotCreateSystemWideElement: return "Cannot create system-wide accessibility element."
        case .noFocusedApplication: return "No focused application found."
        case .noFocusedElement: return "Cannot find the focused text element in the active application."
        case .cannotReadSelectedText: return "Cannot read selected text. The application might not support Accessibility API."
        case .cannotWriteSelectedText: return "Cannot write text. The application might not support Accessibility API."
        }
    }
}

public class AXHelpers {
    
    public static func getFocusedElement() throws -> AXUIElement {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AXError.noFocusedApplication
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Strategies 2-4 may return a focused element that is not the actual text
        // element (no live selection), which previously short-circuited the DFS
        // fallback below and made reading fail on apps where a descendant holds the
        // selection. We now only return a strategy result immediately when it has a
        // non-empty selection; otherwise we remember it and keep looking (DFS), then
        // fall back to it so the user still gets a specific "cannot read" error.
        var fallbackCandidate: AXUIElement?

        // 1. Try System-Wide Focused Element
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

        if error == .success, let element = asElement(focusedElementValue) {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            if pid == app.processIdentifier {
                if elementHasSelectedText(element) { return element }
                if fallbackCandidate == nil { fallbackCandidate = element }
            }
        }

        // 2. Try App-Level Focused Element
        error = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

        if error == .success, let element = asElement(focusedElementValue) {
            if elementHasSelectedText(element) { return element }
            if fallbackCandidate == nil { fallbackCandidate = element }
        }

        // 3. Try the focused window
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
           let focusedWindow = asElement(focusedWindowValue) {
            error = AXUIElementCopyAttributeValue(focusedWindow, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            if error == .success, let element = asElement(focusedElementValue) {
                if elementHasSelectedText(element) { return element }
                if fallbackCandidate == nil { fallbackCandidate = element }
            }
        }

        // 4. Try the main window
        var mainWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue) == .success,
           let mainWindow = asElement(mainWindowValue) {
            error = AXUIElementCopyAttributeValue(mainWindow, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            if error == .success, let element = asElement(focusedElementValue) {
                if elementHasSelectedText(element) { return element }
                if fallbackCandidate == nil { fallbackCandidate = element }
            }
        }

        // 5. Ultimate Fallback: DFS for an element with selected text inside the focused/main window.
        // QUIRK WORKAROUND: Microsoft Outlook (New Outlook) and other Electron/React Native-based apps
        // fail to propagate kAXFocusedUIElementAttribute to the app or window element.
        // We recursively crawl the accessibility tree to find the element that has active selection.
        var visitedCount = 0
        if let window = asElement(focusedWindowValue) {
            if let found = findActiveTextElement(in: window, visitedCount: &visitedCount) {
                return found
            }
        }

        if let window = asElement(mainWindowValue) {
            if let found = findActiveTextElement(in: window, visitedCount: &visitedCount) {
                return found
            }
        }

        // No element reported a live selection. Return the best focused candidate so
        // the caller surfaces "cannot read selected text" rather than "no element".
        if let fallbackCandidate = fallbackCandidate {
            return fallbackCandidate
        }

        throw AXError.noFocusedElement
    }

    /// Safely narrows an Accessibility attribute value (typed as `CFTypeRef` by the
    /// SDK) to an `AXUIElement`. Third-party apps can return `kCFNull` or an
    /// unexpected type; a forced cast would crash Overtype, so we verify the
    /// CoreFoundation type ID first and return nil otherwise, letting the caller fall
    /// through to the next strategy.
    private static func asElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value = value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Safe: the CoreFoundation type ID was verified immediately above.
        return (value as! AXUIElement)
    }

    /// True if the element currently exposes a non-empty `kAXSelectedText`.
    private static func elementHasSelectedText(_ element: AXUIElement) -> Bool {
        var selectedTextValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
              let text = selectedTextValue as? String else {
            return false
        }
        return !text.isEmpty
    }
    
    private static func findActiveTextElement(in element: AXUIElement, depth: Int = 0, visitedCount: inout Int) -> AXUIElement? {
        if depth > 10 { return nil } // Prevent excessive recursion depth
        visitedCount += 1
        if visitedCount > 200 { return nil } // Protect against UI hangs in extremely complex AX trees
        
        var selectedTextValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let text = selectedTextValue as? String, !text.isEmpty {
            return element
        }
        
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let found = findActiveTextElement(in: child, depth: depth + 1, visitedCount: &visitedCount) {
                    return found
                }
            }
        }
        
        return nil
    }
    
    public static func getSelectedText(from element: AXUIElement) throws -> String {
        var selectedTextValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        guard error == .success, let text = selectedTextValue as? String else {
            throw AXError.cannotReadSelectedText
        }
        
        return text
    }
    
    public static func setSelectedText(for element: AXUIElement, text: String) throws {
        let error = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        
        guard error == .success else {
            throw AXError.cannotWriteSelectedText
        }
    }
}
