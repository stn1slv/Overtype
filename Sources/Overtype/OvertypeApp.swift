import Cocoa
import SwiftUI

@main
struct OvertypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindow()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var settingsWindow: NSWindow?
    let engine = ActionEngine()
    let hotkeyManager = HotkeyManager()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Logger.shared.log("Overtype starting up...", level: .info)
        
        // Ensure accessibility permissions are granted
        _ = PermissionManager.checkAndPrompt()
        
        // Setup menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Overtype")
        }
        
        constructMenu()
        
        // Initialize Config
        _ = ConfigStore.shared
        
        // Register hotkeys
        hotkeyManager.registerHotkeys(for: ConfigStore.shared.config.actions) { [weak self] action in
            self?.engine.run(action: action)
        }
    }
    
    func constructMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Overtype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsWindow())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Overtype Settings"
            window.contentViewController = hostingController
            window.center()
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
