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
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
