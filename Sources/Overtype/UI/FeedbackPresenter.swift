import Cocoa
import SwiftUI

public protocol FeedbackPresenting {
    func showLoading(message: String)
    func showError(message: String)
    func hide()
}

public class FeedbackPresenter: FeedbackPresenting {
    public static let shared = FeedbackPresenter()
    
    private var hudWindowController: NSWindowController?
    
    private init() {}
    
    public func showLoading(message: String) {
        DispatchQueue.main.async {
            let view = HUDView(message: message, isError: false)
            self.display(view: view)
        }
    }
    
    public func showError(message: String) {
        DispatchQueue.main.async {
            let view = HUDView(message: message, isError: true)
            self.display(view: view)
            
            // Auto-hide error after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.hide()
            }
        }
    }
    
    public func hide() {
        DispatchQueue.main.async {
            self.hudWindowController?.close()
            self.hudWindowController = nil
        }
    }
    
    private func display(view: HUDView) {
        if hudWindowController == nil {
            let panel = HUDPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
                styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            
            let hostingView = NSHostingView(rootView: view)
            panel.contentView = hostingView
            panel.center()
            
            // Position near bottom of screen
            if let screen = NSScreen.main {
                let frame = panel.frame
                let newOrigin = NSPoint(x: screen.frame.midX - frame.width/2, y: screen.frame.minY + 100)
                panel.setFrameOrigin(newOrigin)
            }
            
            hudWindowController = NSWindowController(window: panel)
        } else if let panel = hudWindowController?.window as? HUDPanel,
                  let hostingView = panel.contentView as? NSHostingView<HUDView> {
            hostingView.rootView = view
        }
        
        hudWindowController?.showWindow(nil)
    }
}

public class HUDPanel: NSPanel {
    public override var canBecomeKey: Bool {
        // Important: Return false so we don't steal focus from the target app!
        return false
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
}

struct HUDView: View {
    let message: String
    let isError: Bool
    
    var body: some View {
        HStack {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.75))
        .cornerRadius(12)
    }
}
