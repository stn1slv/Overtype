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
    // re-check in ActionEngine deliberately stays single-shot and unbounded.
    // The whole read runs under the scoped 2 s AX messaging bound (findings
    // H1/H2), so no single call against a hung target can stall Escape or the
    // hard timeout for longer than that.
    let (element, text) = try AXHelpers.withBoundedAXMessaging { () -> (AXUIElement, String) in
      let element = try AXHelpers.getFocusedElement(wakeDormantTree: true)
      let text = try AXHelpers.getSelectedText(from: element)
      return (element, text)
    }

    guard !text.isEmpty else {
      throw AXError.cannotReadSelectedText
    }

    Logger.shared.log("Successfully read selection of \(text.count) characters.", level: .info)
    Logger.shared.sanitizedLog(sensitiveText: text, context: "Selected text", level: .debug)

    // The pid must belong to the element we read from. Asking NSWorkspace for
    // the frontmost app here would race: dormant-tree recovery can stretch the
    // lookup above by seconds, during which the frontmost app may have changed.
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return Selection(text: text, element: element, pid: pid)
  }
}
