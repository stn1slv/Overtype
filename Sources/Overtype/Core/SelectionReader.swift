import ApplicationServices
import Cocoa

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
    // The initial read opts into dormant-tree recovery (wake flags + bounded
    // retry) so a freshly restarted Teams/VS Code works; the pre-write context
    // re-check in ActionEngine deliberately stays single-shot.
    let element = try AXHelpers.getFocusedElement(wakeDormantTree: true)
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
