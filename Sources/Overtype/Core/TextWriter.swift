import ApplicationServices
import Cocoa

public protocol TextWriting {
  func replaceSelection(
    _ selection: Selection,
    with text: String,
    strategy: WriteStrategy,
    settings: GeneralConfig,
    validateContext: () throws -> Void) throws
}

public class TextWriter: TextWriting {

  public init() {}

  public func replaceSelection(
    _ selection: Selection,
    with text: String,
    strategy: WriteStrategy,
    settings: GeneralConfig,
    validateContext: () throws -> Void
  ) throws {

    switch strategy {
    case .typing:
      // QUIRK WORKAROUND: web/Chromium editors (notably the new Outlook,
      // com.microsoft.Outlook) apply synthetic keystrokes asynchronously and
      // reorder/drop them under a fast burst, corrupting the output. Resolve a
      // per-app typing profile from the source app's bundle id so those apps get
      // a slower, empirically verified cadence while native apps stay fast.
      let bundleID = NSRunningApplication(processIdentifier: selection.pid)?.bundleIdentifier
      let profile = Self.typingProfile(bundleID: bundleID, settings: settings)

      // Say so when the configured chunk size was normalized (finding C2): a
      // corrected value must not be silently substituted, mirroring the
      // retry-delay clamp pattern. typingProfile itself stays pure.
      let configuredChunk =
        bundleID.flatMap { settings.appTypingOverrides?[$0]?.typingChunkSize }
        ?? settings.typingChunkSize
      if let configuredChunk = configuredChunk, configuredChunk != profile.chunkSize {
        Logger.shared.log(
          "Configured typingChunkSize (\(configuredChunk)) is outside "
            + "1...\(Self.maxChunkSizeUTF16); using \(profile.chunkSize).",
          level: .warning)
      }
      try writeViaCGEvent(
        text: text,
        profile: profile,
        speedMultiplier: settings.typingSpeedMultiplier,
        bundleID: bundleID,
        validateContext: validateContext)
    }
  }

  /// Effective typing cadence for one write.
  struct TypingProfile: Equatable {
    let chunkSize: Int
    let delayMicroseconds: Int
  }

  static let defaultChunkSize = 20
  static let defaultDelayMicroseconds = 2000

  /// Upper bound for the text carried by one synthetic keyboard event.
  /// ASSUMPTION (Principle III): the practical cap for
  /// `keyboardSetUnicodeString` is reported at around 20 UTF-16 units; the
  /// diagnostic run recorded in docs/compatibility.md verifies the real value.
  /// A chunk above the cap is silently truncated by the OS after the selection
  /// was already deleted, which is the C2 data-loss path, so this clamp must
  /// stay at or below the verified cap.
  static let maxChunkSizeUTF16 = 20

  /// Resolves the typing cadence for the target app: a per-app override (matched by
  /// bundle id) wins field-by-field over the global defaults, which themselves fall
  /// back to 20 units / 2000 microseconds. A non-positive chunk size behaves like
  /// the Settings field's 0 sentinel ("unset") instead of bypassing the fallback,
  /// and the resolved chunk is clamped to the per-event cap (finding C2); a
  /// negative delay is likewise treated as unset, while an explicit 0 stays valid
  /// ("no delay"). Pure logic, unit-tested.
  static func typingProfile(bundleID: String?, settings: GeneralConfig) -> TypingProfile {
    let globalChunk = usableChunkSize(settings.typingChunkSize) ?? defaultChunkSize
    let globalDelay = usableDelay(settings.typingDelayMicroseconds) ?? defaultDelayMicroseconds

    if let bundleID = bundleID, let override = settings.appTypingOverrides?[bundleID] {
      return TypingProfile(
        chunkSize: min(usableChunkSize(override.typingChunkSize) ?? globalChunk, maxChunkSizeUTF16),
        delayMicroseconds: usableDelay(override.typingDelayMicroseconds) ?? globalDelay
      )
    }
    return TypingProfile(
      chunkSize: min(globalChunk, maxChunkSizeUTF16), delayMicroseconds: globalDelay)
  }

  private static func usableChunkSize(_ value: Int?) -> Int? {
    guard let value = value, value > 0 else { return nil }
    return value
  }

  private static func usableDelay(_ value: Int?) -> Int? {
    guard let value = value, value >= 0 else { return nil }
    return value
  }

  /// Scales the base per-chunk delay by the speed multiplier. A non-positive
  /// multiplier from config is treated as the neutral 1.0. The scaled result is
  /// clamped to `[0, 1_000_000]` microseconds before the `Int()` conversion: a tiny
  /// positive multiplier (or an oversized base delay) can push the value past
  /// `Int.max` or to infinity, which would trap; and no per-chunk delay ever needs to
  /// exceed one second. Pure logic, unit-tested.
  static func effectiveDelayMicroseconds(base: Int, speedMultiplier: Double) -> Int {
    let maxDelayMicroseconds = 1_000_000.0
    let effectiveMultiplier = speedMultiplier > 0 ? speedMultiplier : 1.0
    let scaled = Double(base) / effectiveMultiplier

    if !scaled.isFinite { return Int(maxDelayMicroseconds) }
    if scaled <= 0 { return 0 }
    return Int(min(scaled, maxDelayMicroseconds))
  }

  private func writeViaCGEvent(
    text: String,
    profile: TypingProfile,
    speedMultiplier: Double,
    bundleID: String?,
    validateContext: () throws -> Void
  ) throws {
    // QUIRK WORKAROUND: a synthetic event source that inherits physically held
    // modifiers turns typed characters into keyboard shortcuts (e.g. Cmd+A
    // instead of 'a'), so we wait for the user to release ALL of them. Shift is
    // included (finding H8): a Shift held from a ⌘⇧-style trigger is the same
    // hazard class as Command.

    // Wait for the user to physically release modifiers (Cmd, Option, Control, Shift)
    let maxWaitAttempts = 12
    let waitIntervalMs = 150

    for attempt in 0..<maxWaitAttempts {
      // Allow Escape / context-switch cancellation to interrupt the wait.
      try Task.checkCancellation()

      let currentFlags = CGEventSource.flagsState(.hidSystemState)
      let isHoldingModifiers =
        currentFlags.contains(.maskCommand) || currentFlags.contains(.maskAlternate)
        || currentFlags.contains(.maskControl) || currentFlags.contains(.maskShift)

      if !isHoldingModifiers {
        break
      }

      if attempt == maxWaitAttempts - 1 {
        Logger.shared.log(
          "Modifiers were held too long. Aborting write to prevent unexpected hotkeys.",
          level: .error)
        throw AXError.modifiersHeldTooLong
      }

      Thread.sleep(forTimeInterval: Double(waitIntervalMs) / 1000.0)
    }

    // Non-destructive guard (Principle II): the target context (frontmost app,
    // focused element, and live selection) may have changed during the modifier
    // wait above. Re-validate immediately before the first destructive keystroke,
    // so the delete+type never lands in a different app/element than the one read.
    try validateContext()

    guard let source = CGEventSource(stateID: .privateState) else {
      throw AXError.cannotWriteSelectedText
    }

    // Delete the current selection. We assume the text is currently selected.
    // We press backspace to ensure the text is cleared natively before typing.
    let backspaceKey: CGKeyCode = 51
    postKey(keyCode: backspaceKey, source: source)

    // Let the UI catch up
    Thread.sleep(forTimeInterval: 0.05)

    let chunkSize = profile.chunkSize
    let delayUs = Self.effectiveDelayMicroseconds(
      base: profile.delayMicroseconds, speedMultiplier: speedMultiplier)

    Logger.shared.log(
      "Effective typing config - bundleID: \(bundleID ?? "unknown"), chunkSize: \(chunkSize), delayUS: \(delayUs)",
      level: .info)

    let utf16Chars = Array(text.utf16)
    let totalChars = utf16Chars.count
    let ranges = Self.chunkRanges(for: utf16Chars, chunkSize: chunkSize)
    var chunkCount = 0
    let startTime = Date()

    // Note: once the selection has been deleted above, we intentionally do NOT
    // abort mid-typing on cancellation. Stopping here would leave a half-written
    // replacement in the document, which is worse than finishing. The cancellable
    // interception points are the modifier-release wait and the pre-write
    // re-validation, both before the first destructive keystroke.
    for range in ranges {
      chunkCount += 1
      let chunkLength = range.count
      var chunk = Array(utf16Chars[range])

      guard let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      else {
        // Principle VI: after the destructive backspace there is no safe retry
        // and no safe skip. Silently dropping this chunk would corrupt the
        // replacement while the run still reports success (finding H3). Stop
        // and surface the partial write as a typed error instead.
        Logger.shared.log(
          "CGEvent creation failed at chunk \(chunkCount) of \(ranges.count); aborting write.",
          level: .error)
        throw AXError.writeIncomplete
      }

      eventDown.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: &chunk)
      eventUp.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: &chunk)

      // Explicitly cleared, matching postKey: a chunk event that inherits flags
      // from any source state could deliver shortcuts instead of text (H8).
      eventDown.flags = []
      eventUp.flags = []

      eventDown.post(tap: .cghidEventTap)
      eventUp.post(tap: .cghidEventTap)

      if delayUs > 0 {
        usleep(useconds_t(delayUs))
      }
    }

    let elapsed = Date().timeIntervalSince(startTime)
    let elapsedMs = elapsed * 1000.0
    let avgPerChunk = chunkCount > 0 ? elapsedMs / Double(chunkCount) : 0

    Logger.shared.log(
      String(
        format: "Typing performance - chars: %d, chunks: %d, elapsed: %.1fms, avg/chunk: %.2fms",
        totalChars, chunkCount, elapsedMs, avgPerChunk), level: .info)
  }

  /// Splits a UTF-16 buffer into chunks that target `chunkSize` units each, without
  /// ever splitting a surrogate pair across a boundary. A non-BMP character (emoji,
  /// some CJK) is encoded as a high+low surrogate pair; delivering an unpaired
  /// surrogate to `keyboardSetUnicodeString` produces a broken/replacement
  /// character. When the boundary would fall inside a pair, the chunk SHRINKS by
  /// one unit and the pair moves whole into the next chunk, so no chunk ever
  /// exceeds `chunkSize` (review finding on C2: the earlier extend-by-one produced
  /// a `maxChunkSizeUTF16 + 1` event at the cap, which the OS would silently
  /// truncate into a lone high surrogate after the selection was already deleted).
  /// The single exception is `chunkSize == 1`, where shrinking would empty the
  /// range and stall the loop: there the pair travels as one 2-unit chunk. The
  /// resulting invariant is `chunk.count <= max(chunkSize, 2)`, which stays within
  /// the event cap for every clamped size. Pure logic, unit-tested.
  static func chunkRanges(for utf16: [UInt16], chunkSize: Int) -> [Range<Int>] {
    let total = utf16.count
    guard total > 0 else { return [] }
    // Defense in depth behind typingProfile's normalization: one unbounded
    // range would be silently truncated by the OS event cap (finding C2), so a
    // non-positive size falls back to the default chunking instead.
    guard chunkSize > 0 else { return chunkRanges(for: utf16, chunkSize: defaultChunkSize) }

    var ranges: [Range<Int>] = []
    var i = 0
    while i < total {
      var end = min(i + chunkSize, total)
      // If the chunk would end on a high surrogate that has a following low
      // surrogate, move the boundary so the pair stays together: shrink by one
      // (pair goes to the next chunk, chunk stays <= chunkSize) unless that
      // would empty the range, in which case carry the pair as a 2-unit chunk.
      if end < total {
        let last = utf16[end - 1]
        let isHighSurrogate = (0xD800...0xDBFF).contains(last)
        if isHighSurrogate {
          if end - 1 > i {
            end -= 1
          } else {
            end += 1
          }
        }
      }
      ranges.append(i..<end)
      i = end
    }
    return ranges
  }

  private func postKey(keyCode: CGKeyCode, source: CGEventSource) {
    let eventDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    let eventUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

    eventDown?.flags = []
    eventUp?.flags = []

    eventDown?.post(tap: .cghidEventTap)
    eventUp?.post(tap: .cghidEventTap)
  }
}
