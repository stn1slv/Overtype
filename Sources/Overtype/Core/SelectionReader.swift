import Cocoa
import ApplicationServices

public struct Selection {
    public let text: String
    public let element: AXUIElement
    public let pid: pid_t
}

public protocol SelectionReading {
    func readSelection() throws -> Selection
}

public class SelectionReader: SelectionReading {
    
    public init() {}
    
    public func readSelection() throws -> Selection {
        let element = try AXHelpers.getFocusedElement()
        let text = try AXHelpers.getSelectedText(from: element)
        
        guard !text.isEmpty else {
            throw AXError.cannotReadSelectedText
        }
        
        Logger.shared.log("Successfully read selection of \(text.count) characters.", level: .info)
        Logger.shared.sanitizedLog(sensitiveText: text, context: "Selected text", level: .debug)
        
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return Selection(text: text, element: element, pid: pid)
    }
}
