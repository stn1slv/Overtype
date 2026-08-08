import Cocoa
import Foundation

public class ActionEngine {

  private let selectionReader: SelectionReading
  private let textWriter: TextWriting
  private let sanitizer: ResponseSanitizer
  private var currentTask: Task<Void, Never>?

  public init(
    selectionReader: SelectionReading = SelectionReader(),
    textWriter: TextWriting = TextWriter(),
    sanitizer: ResponseSanitizer = ResponseSanitizer()
  ) {
    self.selectionReader = selectionReader
    self.textWriter = textWriter
    self.sanitizer = sanitizer
  }

  public func run(action: ActionConfig) {
    // Trust is evaluated per run (finding H4): macOS silently revokes the
    // Accessibility permission when the binary changes while the app runs, and
    // a launch-only check then produced the misleading "cannot find the
    // focused text element" for every run. The notification lets AppDelegate
    // start its poll so the Escape monitors self-heal once trust returns.
    guard AXIsProcessTrusted() else {
      Logger.shared.log("Run blocked: Accessibility permission is not granted.", level: .warning)
      FeedbackPresenter.shared.showError(
        message: AXError.accessibilityPermissionRevoked.errorDescription
          ?? "Accessibility permission required")
      NotificationCenter.default.post(name: .overtypeAccessibilityTrustLost, object: nil)
      return
    }

    guard let provider = ProviderRegistry.shared.provider(for: action.providerID) else {
      Logger.shared.log("Provider \(action.providerID) not found.", level: .error)
      FeedbackPresenter.shared.showError(message: "Provider not configured")
      return
    }

    let config = ConfigStore.shared.config

    let providerConfig = config.providers.first(where: { $0.id == action.providerID })

    // Find default model if not overridden
    let defaultModel = providerConfig?.defaultModel ?? "unknown"
    let model = action.model ?? defaultModel
    let retryDelaySeconds =
      providerConfig?.retryDelaySeconds ?? ProviderConfig.defaultRetryDelaySeconds

    // Progress states honor the Show HUD preference; errors are always shown
    // regardless (Principle VI: no silent failure).
    let showHUD = config.global.showHUD
    let showProgress: (String) -> Void = { message in
      if showHUD { FeedbackPresenter.shared.showLoading(message: message) }
    }

    // Captured on the main thread before the task starts, only for the
    // read-timeout error message (finding H1).
    let targetAppName = NSWorkspace.shared.frontmostApplication?.localizedName

    // Serialize runs (Principle II): TextWriter deliberately finishes typing
    // once the first destructive keystroke has landed, so a second hotkey press
    // must not start reading or writing while the previous run may still be
    // typing. The new run cancels the previous task, then awaits its full
    // completion (including its HUD updates) before touching anything.
    let previous = currentTask
    currentTask = Task {
      previous?.cancel()
      _ = await previous?.value

      // A newer run may have superseded this one while it waited.
      guard !Task.isCancelled else { return }

      showProgress("Reading...")
      do {
        let selection = try await Self.readWithHardTimeout(
          seconds: Self.readPhaseTimeoutSeconds, appName: targetAppName, using: selectionReader)

        if selection.text.count > action.maxInputCharacters {
          FeedbackPresenter.shared.showError(message: "Selection too large")
          return
        }

        showProgress("Thinking...")

        let request = TransformRequest(
          text: selection.text,
          systemPrompt: action.systemPrompt,
          userPromptTemplate: action.userPromptTemplate,
          model: model,
          temperature: action.temperature
        )

        let rawResponse = try await Self.transformWithRetry(
          provider: provider, request: request, retryDelaySeconds: retryDelaySeconds,
          showProgress: showProgress)

        try Task.checkCancellation()

        let cleanedResponse = sanitizer.sanitize(
          response: rawResponse, originalText: selection.text, allowNewlines: action.allowNewlines)

        // Non-destructive guard (Principle II): if the model/sanitizer produced an
        // empty result, writing would delete the selection and type nothing back,
        // silently destroying the user's text. Abort before any destructive write.
        guard !cleanedResponse.isEmpty else {
          FeedbackPresenter.shared.showError(message: "AI returned an empty result")
          Logger.shared.log("Action '\(action.title)' aborted: empty replacement.", level: .warning)
          return
        }

        showProgress("Writing...")

        // Context re-check (Principle II). Passed as a closure so the writer can
        // run it *after* its modifier-release wait, immediately before the first
        // destructive keystroke. Validating here (before the wait) would leave a
        // window in which focus/selection changes but the write still proceeds.
        let validateContext: () throws -> Void = {
          // Last cancellation point: the writer calls this immediately before
          // the first destructive keystroke, so an Escape pressed at any time
          // up to here still aborts with the document untouched.
          try Task.checkCancellation()

          let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
          guard currentPID == selection.pid else {
            throw ProviderError.contextChanged
          }

          // Focused element must still be the same one we read from.
          let currentFocused = try? AXHelpers.getFocusedElement()
          guard let currentFocused = currentFocused, CFEqual(currentFocused, selection.element)
          else {
            throw ProviderError.contextChanged
          }

          // The selection must still be live and unchanged. A single backspace
          // deletes the whole selection; if the selection was collapsed or
          // changed since reading, that backspace would corrupt the document.
          let currentSelected = try? AXHelpers.getSelectedText(from: selection.element)
          guard currentSelected == selection.text else {
            throw ProviderError.contextChanged
          }
        }

        try textWriter.replaceSelection(
          selection,
          with: cleanedResponse,
          strategy: action.writeStrategy,
          settings: config.global,
          validateContext: validateContext
        )

        FeedbackPresenter.shared.hide()
        Logger.shared.log("Action '\(action.title)' completed successfully.", level: .info)

      } catch is CancellationError {
        // User-initiated cancel (Escape) is a deliberate no-op, not a failure.
        FeedbackPresenter.shared.hide()
        Logger.shared.log("Action cancelled.", level: .info)
      } catch ProviderError.cancelled {
        FeedbackPresenter.shared.hide()
        Logger.shared.log("Action cancelled.", level: .info)
      } catch ProviderError.contextChanged {
        // Target context changed since reading; the write was intentionally
        // skipped. Surface it (no silent failure) instead of just hiding.
        FeedbackPresenter.shared.showError(
          message: ProviderError.contextChanged.errorDescription
            ?? "Target changed; nothing was changed.")
        Logger.shared.log("Action skipped: target context changed before writing.", level: .warning)
      } catch let ProviderError.apiError(statusCode, message) {
        // The HUD (not a log) may show the specific server message so the user
        // can tell 401/429/500 apart. Keep the raw server body out of info+
        // logs, since an error body can echo fragments of the submitted text.
        FeedbackPresenter.shared.showError(message: "API Error \(statusCode): \(message)")
        Logger.shared.log("Action failed: API error \(statusCode).", level: .error)
        Logger.shared.sanitizedLog(sensitiveText: message, context: "API error body", level: .debug)
      } catch let error as ProviderError {
        // Log the redaction-safe label, never the error itself: cases such as
        // .responseBlocked(reason:) interpolate their associated value, and an
        // error payload can echo fragments of the submitted text. The HUD may
        // still show the full description; only info+ logs are constrained.
        FeedbackPresenter.shared.showError(message: error.localizedDescription)
        Logger.shared.log("Action failed: \(error.logLabel).", level: .error)
      } catch {
        FeedbackPresenter.shared.showError(message: error.localizedDescription)
        Logger.shared.log("Action failed: \(error)", level: .error)
      }
    }
  }

  /// Hard timeout for the read phase (constitution VI requires one; the 30 s
  /// value was clarified in the 009 spec session). Normal reads finish in well
  /// under a second and the verified Teams dormant-tree recovery in about
  /// 3.6 s; this bound only ends runs against a pathological target that
  /// nobody cancelled.
  static let readPhaseTimeoutSeconds: Double = 30

  /// Races the synchronous, uninterruptible AX read against a cancellable
  /// sleep (finding H1). On timeout the group is cancelled and the typed
  /// readTimedOut error surfaces; the cancelled read child observes
  /// cancellation at its next check (each AX call is bounded by the scoped 2 s
  /// messaging timeout) before the group returns, so the wait after a timeout
  /// is at most about one AX call.
  static func readWithHardTimeout(
    seconds: Double, appName: String?, using reader: SelectionReading
  ) async throws -> Selection {
    try await withThrowingTaskGroup(of: Selection.self) { group in
      group.addTask {
        try reader.readSelection()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw AXError.readTimedOut(appName: appName)
      }
      guard let result = try await group.next() else {
        throw AXError.readTimedOut(appName: appName)
      }
      group.cancelAll()
      return result
    }
  }

  /// Upper bound for the retry pause. The Providers tab slider already caps at
  /// 5s; this exists for hand-edited configs, where a longer wait is
  /// indistinguishable from the app having hung.
  static let maxRetryDelaySeconds: Double = 60

  /// Converts a configured retry delay into nanoseconds for `Task.sleep`.
  ///
  /// Clamped at both ends because `config.json` is a documented hand-editing
  /// surface and both extremes trap in the `UInt64(...)` conversion below: a
  /// negative or non-finite value has no `UInt64` representation, and a large
  /// one (`1e11`, say) overflows with "Double value cannot be converted to
  /// UInt64". Returns 0 to mean "retry immediately, no sleep". Pure logic,
  /// unit-tested, and deliberately free of logging so it stays pure; callers
  /// report a clamp via `isRetryDelayInRange`.
  static func retryDelayNanoseconds(forSeconds seconds: Double) -> UInt64 {
    // NaN fails both comparisons, so it also lands on 0.
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return UInt64(min(seconds, maxRetryDelaySeconds) * 1_000_000_000)
  }

  /// Whether a configured delay is used as written rather than clamped. Lets the
  /// caller warn instead of silently substituting a different value, the same
  /// reason the Providers tab loads `retryDelaySeconds` unclamped.
  static func isRetryDelayInRange(_ seconds: Double) -> Bool {
    seconds.isFinite && (0...maxRetryDelaySeconds).contains(seconds)
  }

  /// Runs the provider call, retrying once if the failure was transient.
  ///
  /// Only `ProviderError.isRetryable` failures are retried; everything else,
  /// including cancellation, propagates from the first attempt so the user sees
  /// the real error without waiting through a second doomed request. A failed
  /// call has changed nothing in the document (the write happens later, after
  /// the context re-check), so repeating it is safe under Principle II.
  ///
  /// `static` and `internal` on purpose: it touches no instance state, so tests
  /// can drive it with a fake `AIProvider` without standing up an engine or
  /// reaching through `ProviderRegistry.shared`.
  static func transformWithRetry(
    provider: AIProvider,
    request: TransformRequest,
    retryDelaySeconds: Double,
    showProgress: (String) -> Void
  ) async throws -> String {
    do {
      return try await provider.transform(request)
    } catch let error as ProviderError where error.isRetryable {
      // Escape pressed during the failed attempt must abort here rather than
      // start a second request.
      try Task.checkCancellation()

      Logger.shared.log(
        "Provider call failed (\(error.logLabel)); retrying once.", level: .warning)
      showProgress("Retrying...")

      // Brief pause so a rate limit has a chance to clear before the second
      // attempt. Task.sleep is cancellable, so Escape during the wait still
      // aborts the run with nothing written.
      //
      // A hand-edited value outside the supported range is clamped rather than
      // honored, so say so (Principle IV): otherwise a configured 120s behaves
      // as 60s with nothing to explain the difference.
      if !Self.isRetryDelayInRange(retryDelaySeconds) {
        Logger.shared.log(
          "Configured retryDelaySeconds (\(retryDelaySeconds)) is outside "
            + "0...\(Self.maxRetryDelaySeconds)s; clamping.", level: .warning)
      }
      let delayNanoseconds = Self.retryDelayNanoseconds(forSeconds: retryDelaySeconds)
      if delayNanoseconds > 0 {
        try await Task.sleep(nanoseconds: delayNanoseconds)
      }

      return try await provider.transform(request)
    }
  }

  public func cancel() {
    // The run task owns the HUD lifecycle: its catch/completion paths hide it.
    // Hiding here would blank the HUD while a non-abortable write is still
    // typing, which looks like a stop that did not happen.
    currentTask?.cancel()
  }
}
