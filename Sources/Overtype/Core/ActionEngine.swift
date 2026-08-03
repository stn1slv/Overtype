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
    guard let provider = ProviderRegistry.shared.provider(for: action.providerID) else {
      Logger.shared.log("Provider \(action.providerID) not found.", level: .error)
      FeedbackPresenter.shared.showError(message: "Provider not configured")
      return
    }

    let config = ConfigStore.shared.config

    // Find default model if not overridden
    let defaultModel =
      config.providers.first(where: { $0.id == action.providerID })?.defaultModel ?? "unknown"
    let model = action.model ?? defaultModel

    // Progress states honor the Show HUD preference; errors are always shown
    // regardless (Principle VI: no silent failure).
    let showHUD = config.global.showHUD
    let showProgress: (String) -> Void = { message in
      if showHUD { FeedbackPresenter.shared.showLoading(message: message) }
    }

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
        let selection = try selectionReader.readSelection()

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

        let rawResponse = try await provider.transform(request)

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
      } catch {
        FeedbackPresenter.shared.showError(message: error.localizedDescription)
        Logger.shared.log("Action failed: \(error)", level: .error)
      }
    }
  }

  public func cancel() {
    // The run task owns the HUD lifecycle: its catch/completion paths hide it.
    // Hiding here would blank the HUD while a non-abortable write is still
    // typing, which looks like a stop that did not happen.
    currentTask?.cancel()
  }
}
