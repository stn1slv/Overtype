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
        
        var focusedElementValue: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        
        if error == .success, let element = focusedElementValue {
            return element as! AXUIElement
        }
        
        // Fallback 1: Try the focused window
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
           let focusedWindow = focusedWindowValue {
            error = AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            if error == .success, let element = focusedElementValue {
                return element as! AXUIElement
            }
        }
        
        // Fallback 2: Try the main window
        var mainWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowValue) == .success,
           let mainWindow = mainWindowValue {
            error = AXUIElementCopyAttributeValue(mainWindow as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            if error == .success, let element = focusedElementValue {
                return element as! AXUIElement
            }
        }
        
        throw AXError.noFocusedElement
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
