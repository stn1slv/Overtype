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
        
        // 1. Try System-Wide Focused Element
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementValue: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        
        if error == .success, let element = focusedElementValue {
            var pid: pid_t = 0
            AXUIElementGetPid(element as! AXUIElement, &pid)
            if pid == app.processIdentifier {
                return element as! AXUIElement
            }
        }
        
        // 2. Try App-Level Focused Element
        error = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        
        if error == .success, let element = focusedElementValue {
            return element as! AXUIElement
        }
        
        // 3. Try the focused window
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
           let focusedWindow = focusedWindowValue {
            error = AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            if error == .success, let element = focusedElementValue {
                return element as! AXUIElement
            }
        }
        
        // 4. Try the main window
        var mainWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue) == .success,
           let mainWindow = mainWindowValue {
            error = AXUIElementCopyAttributeValue(mainWindow as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            if error == .success, let element = focusedElementValue {
                return element as! AXUIElement
            }
        }
        
        // 5. Ultimate Fallback: DFS for an element with selected text inside the focused/main window
        if let window = focusedWindowValue {
            if let found = findActiveTextElement(in: window as! AXUIElement) {
                return found
            }
        }
        
        if let window = mainWindowValue {
            if let found = findActiveTextElement(in: window as! AXUIElement) {
                return found
            }
        }
        
        throw AXError.noFocusedElement
    }
    
    private static func findActiveTextElement(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 15 { return nil } // Prevent infinite/excessive recursion
        
        var selectedTextValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
           let text = selectedTextValue as? String, !text.isEmpty {
            return element
        }
        
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
           let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let found = findActiveTextElement(in: child, depth: depth + 1) {
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
