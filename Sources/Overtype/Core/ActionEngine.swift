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
                    temperature: action.temperature,
                    timeoutSeconds: 30.0
                )
                
                let rawResponse = try await provider.transform(request)
                
                try Task.checkCancellation()
                
                let cleanedResponse = sanitizer.sanitize(response: rawResponse, originalText: selection.text)
                
                FeedbackPresenter.shared.showLoading(message: "Writing...")
                
                let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                guard currentPID == selection.pid else {
                    throw ProviderError.cancelled // Or a specific context changed error
                }
                
                try textWriter.replaceSelection(
                    selection,
                    with: cleanedResponse,
                    strategy: action.writeStrategy,
                    settings: config.global
                )
                
                FeedbackPresenter.shared.hide()
                Logger.shared.log("Action '\(action.title)' completed successfully.", level: .info)
                
            } catch is CancellationError {
                FeedbackPresenter.shared.hide()
                Logger.shared.log("Action cancelled.", level: .info)
            } catch ProviderError.cancelled {
                FeedbackPresenter.shared.hide()
                Logger.shared.log("Action cancelled due to context switch.", level: .info)
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
