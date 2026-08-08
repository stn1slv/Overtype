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
  var globalEscapeMonitor: Any?
  var localEscapeMonitor: Any?
  var permissionPollTimer: Timer?
  let engine = ActionEngine()
  let hotkeyManager = HotkeyManager()

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    // Enforce a single running instance. A second menu-bar copy would register
    // duplicate global hotkeys that fight each other, so if another instance is
    // already running we quit before creating the status item or any hotkeys.
    // LSMultipleInstancesProhibited in Info.plist blocks the normal second
    // launch race-free; this runtime check is a backstop for `open -n`. We quit
    // only if an older instance (smaller PID) exists, so a simultaneous launch
    // leaves exactly one survivor instead of both quitting.
    if let bundleID = Bundle.main.bundleIdentifier {
      let ownPID = getpid()
      let hasOlderInstance = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .contains { $0.processIdentifier < ownPID }
      if hasOlderInstance {
        Logger.shared.log(
          "Another Overtype instance is already running; exiting this one.", level: .info)
        NSApp.terminate(nil)
        return
      }
    }

    Logger.shared.log("Overtype starting up...", level: .info)

    // Ensure accessibility permissions are granted
    let isTrusted = PermissionManager.checkAndPrompt()

    // Setup menu bar icon
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Overtype")
    }

    constructMenu()

    // Initialize Config
    _ = ConfigStore.shared

    // Surface a config file that could not be read (no silent failure): the
    // defaults are in use and the unreadable file was preserved on disk.
    if let failureMessage = ConfigStore.shared.loadFailureMessage {
      // An accessory app is not active at launch; without activation the modal
      // alert can appear unfocused behind other windows.
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "Configuration could not be loaded"
      alert.informativeText = failureMessage
      alert.alertStyle = .warning
      alert.runModal()
    }

    // A partially readable config is surfaced too (finding C3): the app runs,
    // but some values were ignored or defaulted, and only the file's author
    // can repair them.
    if let warningMessage = ConfigStore.shared.loadWarningMessage {
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "Some configuration values were ignored"
      alert.informativeText = warningMessage
      alert.alertStyle = .warning
      alert.runModal()
    }

    // Register hotkeys
    hotkeyManager.registerHotkeys(for: ConfigStore.shared.config.actions) { [weak self] action in
      self?.engine.run(action: action)
    }

    // Register Escape key to cancel in-flight tasks
    setupEscapeMonitors()

    if !isTrusted {
      startPermissionPollIfNeeded()
    }

    // Listen for configuration changes
    NotificationCenter.default.addObserver(
      self, selector: #selector(configDidChange),
      name: .overtypeConfigDidChange, object: nil)

    // A run that finds the permission revoked mid-session reports it here, so
    // the same poll/reinstall path heals the monitors after a re-grant
    // (finding H4).
    NotificationCenter.default.addObserver(
      self, selector: #selector(accessibilityTrustLost),
      name: .overtypeAccessibilityTrustLost, object: nil)
  }

  @objc func accessibilityTrustLost() {
    startPermissionPollIfNeeded()
  }

  // QUIRK WORKAROUND: a global NSEvent monitor installed while the process is
  // not Accessibility-trusted never starts delivering events, even after the
  // user grants the permission. On the standard first-run flow (grant in
  // System Settings without relaunching) Escape-cancel would silently never
  // work, so poll until trust appears and then reinstall the monitors. The
  // same applies after a mid-session revoke and re-grant (finding H4), which
  // is routine after a binary update re-signs the app.
  func startPermissionPollIfNeeded() {
    guard permissionPollTimer == nil else { return }
    let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] timer in
      guard AXIsProcessTrusted() else { return }
      timer.invalidate()
      self?.permissionPollTimer = nil
      self?.reinstallEscapeMonitors()
      Logger.shared.log(
        "Accessibility permission granted; escape monitors reinstalled.", level: .info)
    }
    // .common instead of the default mode, so polling keeps firing while the
    // run loop is tracking a menu or a drag (default-mode timers pause then).
    RunLoop.main.add(timer, forMode: .common)
    permissionPollTimer = timer
  }

  func setupEscapeMonitors() {
    let handler: (NSEvent) -> NSEvent? = { [weak self] event in
      if event.keyCode == 53 {  // kVK_Escape
        self?.engine.cancel()
      }
      return event
    }

    globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      _ = handler(event)
    }

    localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler)
  }

  func reinstallEscapeMonitors() {
    if let monitor = globalEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      globalEscapeMonitor = nil
    }
    if let monitor = localEscapeMonitor {
      NSEvent.removeMonitor(monitor)
      localEscapeMonitor = nil
    }
    setupEscapeMonitors()
  }

  func constructMenu() {
    let menu = NSMenu()

    menu.addItem(
      NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit Overtype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    statusItem.menu = menu
  }

  @objc func openSettings() {
    if settingsWindow == nil {
      let hostingController = NSHostingController(rootView: SettingsWindow())
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
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

  @objc func configDidChange() {
    Logger.shared.log("Configuration changed. Reloading providers and hotkeys...", level: .info)
    ProviderRegistry.shared.reloadProviders()
    hotkeyManager.registerHotkeys(for: ConfigStore.shared.config.actions) { [weak self] action in
      self?.engine.run(action: action)
    }
  }
}
