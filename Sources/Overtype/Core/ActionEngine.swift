import Foundation
import Cocoa

public class ActionEngine {
    
    private let selectionReader: SelectionReading
    private let textWriter: TextWriting
    private let sanitizer: ResponseSanitizer
    private var currentTask: Task<Void, Never>?
    
    public init(selectionReader: SelectionReading = SelectionReader(),
                textWriter: TextWriting = TextWriter(),
                sanitizer: ResponseSanitizer = ResponseSanitizer()) {
        self.selectionReader = selectionReader
        self.textWriter = textWriter
        self.sanitizer = sanitizer
    }
    
    public func run(action: ActionConfig) {
        // Cancel any in-flight task
        currentTask?.cancel()
        
        guard let provider = ProviderRegistry.shared.provider(for: action.providerID) else {
            Logger.shared.log("Provider \(action.providerID) not found.", level: .error)
            FeedbackPresenter.shared.showError(message: "Provider not configured")
            return
        }
        
        let config = ConfigStore.shared.config
        
        // Find default model if not overridden
        let defaultModel = config.providers.first(where: { $0.id == action.providerID })?.defaultModel ?? "unknown"
        let model = action.model ?? defaultModel
        
        FeedbackPresenter.shared.showLoading(message: "Reading...")
        
        currentTask = Task {
            do {
                let selection = try selectionReader.readSelection()
                
                if selection.text.count > action.maxInputCharacters {
                    FeedbackPresenter.shared.showError(message: "Selection too large")
                    return
                }
                
                FeedbackPresenter.shared.showLoading(message: "Thinking...")
                
                let request = TransformRequest(
                    text: selection.text,
                    systemPrompt: action.systemPrompt,
                    userPromptTemplate: action.userPromptTemplate,
                    model: model,
                    temperature: action.temperature
                )
                
                let rawResponse = try await provider.transform(request)
                
                try Task.checkCancellation()
                
                let cleanedResponse = sanitizer.sanitize(response: rawResponse, originalText: selection.text, allowNewlines: action.allowNewlines)

                // Non-destructive guard (Principle II): if the model/sanitizer produced an
                // empty result, writing would delete the selection and type nothing back,
                // silently destroying the user's text. Abort before any destructive write.
                guard !cleanedResponse.isEmpty else {
                    FeedbackPresenter.shared.showError(message: "AI returned an empty result")
                    Logger.shared.log("Action '\(action.title)' aborted: empty replacement.", level: .warning)
                    return
                }

                FeedbackPresenter.shared.showLoading(message: "Writing...")

                // Context re-check (Principle II). Passed as a closure so the writer can
                // run it *after* its modifier-release wait, immediately before the first
                // destructive keystroke. Validating here (before the wait) would leave a
                // window in which focus/selection changes but the write still proceeds.
                let validateContext: () throws -> Void = {
                    let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                    guard currentPID == selection.pid else {
                        throw ProviderError.contextChanged
                    }

                    // Focused element must still be the same one we read from.
                    let currentFocused = try? AXHelpers.getFocusedElement()
                    guard let currentFocused = currentFocused, CFEqual(currentFocused, selection.element) else {
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
                FeedbackPresenter.shared.showError(message: ProviderError.contextChanged.errorDescription ?? "Target changed; nothing was changed.")
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
        currentTask?.cancel()
        currentTask = nil
        FeedbackPresenter.shared.hide()
    }
}
