import ApplicationServices
import Cocoa

public enum AXError: Error, LocalizedError {
  case cannotCreateSystemWideElement
  case noFocusedApplication
  case noFocusedElement
  case cannotReadSelectedText
  case cannotWriteSelectedText
  case modifiersHeldTooLong
  case writeIncomplete
  case readTimedOut(appName: String?)
  case accessibilityPermissionRevoked

  public var errorDescription: String? {
    switch self {
    case .cannotCreateSystemWideElement: return "Cannot create system-wide accessibility element."
    case .noFocusedApplication: return "No focused application found."
    case .noFocusedElement: return "Cannot find the focused text element in the active application."
    case .cannotReadSelectedText:
      return "Cannot read selected text. The application might not support Accessibility API."
    case .cannotWriteSelectedText:
      return "Cannot write text. The application might not support Accessibility API."
    case .modifiersHeldTooLong:
      return
        "Modifier keys were held too long. Release Cmd/Option/Control/Shift and try again. Nothing was changed."
    case .writeIncomplete:
      return
        "Writing was interrupted; the replacement may be incomplete. Use Undo (Cmd+Z) in the target application to restore the original text."
    case .readTimedOut(let appName):
      return
        "\(appName ?? "The target application") did not respond while reading the selection. Nothing was changed."
    case .accessibilityPermissionRevoked:
      return
        "Accessibility permission is missing. Grant it to Overtype in System Settings > Privacy & Security > Accessibility, then try again."
    }
  }
}

public class AXHelpers {

  /// Empirically validated dormant-tree recovery configuration
  /// (axprobe findings 2026-07-31, binding conclusion #3; re-verified 2026-08-02).
  /// 24 attempts, not the findings' 12: the acceptance run against a truly cold
  /// Teams (2026-08-02 21:40) showed the focused element appears quickly after
  /// the wake but its selection attribute populates only ~2.7 s in; 12 x 150 ms
  /// (1.8 s) missed it, 24 x 150 ms (~3.5 s) covers it with margin.
  private static let recoveryAttempts = 24
  private static let recoveryIntervalSeconds: TimeInterval = 0.15
  private static let recoveryMessagingTimeoutSeconds: Float = 2.0

  /// Bounds every AX call made inside `body` to the 2 s messaging timeout, and
  /// restores the system default on exit (findings H1/H2). Setting the timeout
  /// on the SYSTEM-WIDE element sets the process-wide default, which is exactly
  /// what makes it cover strategy 1's system-wide query and every element the
  /// DFS visits, and exactly why it must be scoped: the old recovery set it
  /// permanently, silently changing AX behavior for every later run and making
  /// the per-app findings in docs/compatibility.md order-dependent. Per the AX
  /// contract, a timeout of 0 restores the global default.
  static func withBoundedAXMessaging<T>(_ body: () throws -> T) rethrows -> T {
    let systemWideElement = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(systemWideElement, recoveryMessagingTimeoutSeconds)
    defer { AXUIElementSetMessagingTimeout(systemWideElement, 0) }
    return try body()
  }

  /// - Parameter wakeDormantTree: when true and no strategy finds any element,
  ///   escalate once: set the assistive-client wake flags on the target app and
  ///   retry the lookup for a bounded window. Only the initial selection read
  ///   opts in; the pre-write context re-check stays single-shot so a genuine
  ///   context change still aborts fast (Principle II).
  public static func getFocusedElement(wakeDormantTree: Bool = false) throws -> AXUIElement {
    guard let app = NSWorkspace.shared.frontmostApplication else {
      throw AXError.noFocusedApplication
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)

    // Strategies 2-4 may return a focused element that is not the actual text
    // element (no live selection), which previously short-circuited the DFS
    // fallback below and made reading fail on apps where a descendant holds the
    // selection. We now only return a strategy result immediately when it has a
    // non-empty selection; otherwise we remember it and keep looking (DFS), then
    // fall back to it so the user still gets a specific "cannot read" error.
    var fallbackCandidate: AXUIElement?

    // Escape must stay responsive between every strategy (finding H1): each AX
    // call below blocks synchronously against the target process, so these are
    // the only opportunities cancellation has during the lookup.
    try Task.checkCancellation()

    // 1. Try System-Wide Focused Element
    let systemWideElement = AXUIElementCreateSystemWide()
    var focusedElementValue: CFTypeRef?
    var error = AXUIElementCopyAttributeValue(
      systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

    if error == .success, let element = asElement(focusedElementValue) {
      var pid: pid_t = 0
      AXUIElementGetPid(element, &pid)
      if pid == app.processIdentifier {
        if elementHasSelectedText(element) { return element }
        if fallbackCandidate == nil { fallbackCandidate = element }
      }
    }

    // 2. Try App-Level Focused Element
    try Task.checkCancellation()
    error = AXUIElementCopyAttributeValue(
      appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

    if error == .success, let element = asElement(focusedElementValue) {
      if elementHasSelectedText(element) { return element }
      if fallbackCandidate == nil { fallbackCandidate = element }
    }

    // 3. Try the focused window
    try Task.checkCancellation()
    var focusedWindowValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue) == .success,
      let focusedWindow = asElement(focusedWindowValue)
    {
      error = AXUIElementCopyAttributeValue(
        focusedWindow, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
      if error == .success, let element = asElement(focusedElementValue) {
        if elementHasSelectedText(element) { return element }
        if fallbackCandidate == nil { fallbackCandidate = element }
      }
    }

    // 4. Try the main window
    try Task.checkCancellation()
    var mainWindowValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      appElement, kAXMainWindowAttribute as CFString, &mainWindowValue) == .success,
      let mainWindow = asElement(mainWindowValue)
    {
      error = AXUIElementCopyAttributeValue(
        mainWindow, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
      if error == .success, let element = asElement(focusedElementValue) {
        if elementHasSelectedText(element) { return element }
        if fallbackCandidate == nil { fallbackCandidate = element }
      }
    }

    // 5. Ultimate Fallback: DFS for an element with selected text inside the focused/main window.
    // QUIRK WORKAROUND: Microsoft Outlook (New Outlook) and other Electron/React Native-based apps
    // fail to propagate kAXFocusedUIElementAttribute to the app or window element.
    // We recursively crawl the accessibility tree to find the element that has active selection.
    var visitedCount = 0
    if let window = asElement(focusedWindowValue) {
      if let found = try findActiveTextElement(in: window, visitedCount: &visitedCount) {
        return found
      }
    }

    if let window = asElement(mainWindowValue) {
      if let found = try findActiveTextElement(in: window, visitedCount: &visitedCount) {
        return found
      }
    }

    // 6. Dormant-tree recovery. Entered only when the strategies above found
    // NOTHING (not even a selection-less focused element): that is the
    // signature of a lazily built accessibility tree that has not been woken
    // yet (Microsoft Teams after a process restart, VS Code shortly after
    // launch). If any element was found, the tree is awake and retrying
    // cannot conjure a selection, so we skip recovery and fail fast.
    if wakeDormantTree && fallbackCandidate == nil {
      Logger.shared.log(
        "No focused element found; attempting dormant-tree recovery (pid \(app.processIdentifier)).",
        level: .info)
      wakeDormantAccessibilityTree(appElement: appElement)
      // Whatever the retry finds (with or without a live selection) is returned
      // via the fallback path below; the caller reads the selection itself.
      fallbackCandidate = try retryFocusLookup(
        appElement: appElement, targetPid: app.processIdentifier)
    }

    // No element reported a live selection. Return the best focused candidate so
    // the caller surfaces "cannot read selected text" rather than "no element".
    if let fallbackCandidate = fallbackCandidate {
      return fallbackCandidate
    }

    throw AXError.noFocusedElement
  }

  /// Signals "an assistive client is present" so lazily initialized apps build
  /// their accessibility tree. Both set calls deliberately ignore the returned
  /// error code:
  /// - QUIRK WORKAROUND (verified 2026-08-02): Microsoft Teams returns
  ///   `.notImplemented` (-25208) for `AXEnhancedUserInterface` yet HONORS the
  ///   write - the value read back flips to true and the dormant tree
  ///   activates. The return code is not evidence of failure, just as a
  ///   success code is not evidence of effect (constitution Principle III).
  /// - `AXManualAccessibility` is the Electron-specific equivalent (accepted
  ///   by VS Code and Claude desktop, rejected by Teams with
  ///   `.attributeUnsupported`; axprobe findings 2026-07-31). Setting both
  ///   covers both app families.
  private static func wakeDormantAccessibilityTree(appElement: AXUIElement) {
    _ = AXUIElementSetAttributeValue(
      appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    _ = AXUIElementSetAttributeValue(
      appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
  }

  /// Retries the focused-element lookup after a wake-up, app element first
  /// (the only path that works for Teams; the system-wide element is a
  /// secondary), for a bounded window. Returns the first element exposing a
  /// non-empty selection, else the last selection-less focused element found
  /// (so the caller can surface the specific "cannot read" error), else nil.
  /// Checks for task cancellation each attempt so Escape stays responsive.
  private static func retryFocusLookup(
    appElement: AXUIElement, targetPid: pid_t
  ) throws -> AXUIElement? {
    // Per-element bound for the app element (harmless, dies with the handle).
    // The former SYSTEM-WIDE timeout set here was process-global and never
    // restored (finding H2); the scoped bound now comes from
    // withBoundedAXMessaging around the whole read phase.
    AXUIElementSetMessagingTimeout(appElement, recoveryMessagingTimeoutSeconds)
    let systemWideElement = AXUIElementCreateSystemWide()

    var candidate: AXUIElement?
    for attempt in 1...recoveryAttempts {
      try Task.checkCancellation()

      for source in [appElement, systemWideElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
          source, kAXFocusedUIElementAttribute as CFString, &value)
        if error == .success, let element = asElement(value) {
          // The system-wide element can report focus in a different app; only
          // accept elements owned by the target (mirrors strategy 1's check).
          var elementPid: pid_t = 0
          AXUIElementGetPid(element, &elementPid)
          guard elementPid == targetPid else { continue }
          if elementHasSelectedText(element) {
            Logger.shared.log(
              "Dormant-tree recovery found the selection on attempt \(attempt).", level: .info)
            return element
          }
          candidate = element
        }
      }

      // No sleep after the last attempt; it would only delay the failure.
      if attempt < recoveryAttempts {
        Thread.sleep(forTimeInterval: recoveryIntervalSeconds)
      }
    }

    Logger.shared.log(
      "Dormant-tree recovery exhausted after \(recoveryAttempts) attempts "
        + "(focused element found: \(candidate != nil)).",
      level: .warning)
    return candidate
  }

  /// Safely narrows an Accessibility attribute value (typed as `CFTypeRef` by the
  /// SDK) to an `AXUIElement`. Third-party apps can return `kCFNull` or an
  /// unexpected type; a forced cast would crash Overtype, so we verify the
  /// CoreFoundation type ID first and return nil otherwise, letting the caller fall
  /// through to the next strategy.
  private static func asElement(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value = value else { return nil }
    guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    // Safe: the CoreFoundation type ID was verified immediately above.
    return (value as! AXUIElement)
  }

  /// True if the element currently exposes a non-empty `kAXSelectedText`.
  private static func elementHasSelectedText(_ element: AXUIElement) -> Bool {
    var selectedTextValue: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
      let text = selectedTextValue as? String
    else {
      return false
    }
    return !text.isEmpty
  }

  private static func findActiveTextElement(
    in element: AXUIElement, depth: Int = 0, visitedCount: inout Int
  ) throws -> AXUIElement? {
    if depth > 10 { return nil }  // Prevent excessive recursion depth
    visitedCount += 1
    if visitedCount > 200 { return nil }  // Protect against UI hangs in extremely complex AX trees

    // Every node visit is 1-2 blocking AX calls against the target; without a
    // per-node check, Escape stays dead for the whole crawl (finding H1).
    try Task.checkCancellation()

    var selectedTextValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      element, kAXSelectedTextAttribute as CFString, &selectedTextValue) == .success,
      let text = selectedTextValue as? String, !text.isEmpty
    {
      return element
    }

    var childrenValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
      == .success,
      let children = childrenValue as? [AXUIElement]
    {
      for child in children {
        if let found = try findActiveTextElement(
          in: child, depth: depth + 1, visitedCount: &visitedCount)
        {
          return found
        }
      }
    }

    return nil
  }

  public static func getSelectedText(from element: AXUIElement) throws -> String {
    var selectedTextValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(
      element, kAXSelectedTextAttribute as CFString, &selectedTextValue)

    guard error == .success, let text = selectedTextValue as? String else {
      throw AXError.cannotReadSelectedText
    }

    return text
  }

  public static func setSelectedText(for element: AXUIElement, text: String) throws {
    let error = AXUIElementSetAttributeValue(
      element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)

    guard error == .success else {
      throw AXError.cannotWriteSelectedText
    }
  }
}
