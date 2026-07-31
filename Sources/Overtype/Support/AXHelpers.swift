import Cocoa
import ApplicationServices

public enum AXError: Error {
    case cannotCreateSystemWideElement
    case noFocusedApplication
    case noFocusedElement
    case cannotReadSelectedText
    case cannotWriteSelectedText
}

public class AXHelpers {
    
    public static func getFocusedElement() throws -> AXUIElement {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw AXError.noFocusedApplication
        }
        
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        
        var focusedElementValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        
        guard error == .success, let element = focusedElementValue else {
            throw AXError.noFocusedElement
        }
        
        return element as! AXUIElement
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
