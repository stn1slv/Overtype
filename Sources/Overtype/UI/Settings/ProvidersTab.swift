import SwiftUI

public struct ProvidersTab: View {
  @ObservedObject var viewModel: SettingsViewModel

  @State private var editingProvider: ProviderConfig? = nil
  @State private var isShowingEditSheet = false

  // Form fields
  @State private var name = ""
  @State private var kind: ProviderKind = .openAICompatible
  @State private var baseURLString = ""
  @State private var defaultModel = ""
  @State private var timeout = 30.0
  @State private var retryDelay = ProviderConfig.defaultRetryDelaySeconds
  @State private var apiKey = ""
  @State private var errorMessage: String? = nil

  /// Kinds selectable in the form. All four are implemented as of
  /// specs/008-ollama-provider; the fallback below stays because a hand-edited
  /// config may still name a kind this list does not, and editing such a
  /// provider must not silently change its kind.
  private var selectableKinds: [ProviderKind] {
    var kinds: [ProviderKind] = [.openAICompatible, .gemini, .anthropic, .ollama]
    if let current = editingProvider?.kind, !kinds.contains(current) {
      kinds.append(current)
    }
    return kinds
  }

  /// Hint shown in the empty Base URL field.
  ///
  /// The hints are not all the same kind of statement. Gemini, Anthropic and
  /// Ollama fall back to a documented default host when the field is blank, so
  /// theirs are prefixed "Default:" and leaving the field empty is a valid
  /// choice. An OpenAI-compatible provider has no fallback —
  /// `OpenAICompatibleProvider` throws `.invalidURL` when `baseURL` is nil — so
  /// its hint is an example to copy, and leaving the field empty fails at run
  /// time.
  private func baseURLPlaceholder(for kind: ProviderKind) -> String {
    switch kind {
    case .openAICompatible: return "https://api.openai.com/v1"
    case .gemini: return "Default: generativelanguage.googleapis.com"
    case .anthropic: return "Default: api.anthropic.com"
    case .ollama: return "Default: http://localhost:11434"
    }
  }

  /// Placeholder shown inside the empty API key field.
  ///
  /// Ollama is the one kind that normally needs no credential, because the
  /// service runs on the user's own machine. A prompt that reads as mandatory
  /// would make the normal setup look broken, so it is marked optional here
  /// (specs/008-ollama-provider FR-005). An empty value is accepted for every
  /// kind by `SettingsViewModel.saveProvider`; only the wording differs.
  ///
  /// LAYOUT CONSTRAINT: this wording must stay out of the field's *label*. A
  /// macOS `Form` sizes one shared label column to the widest label in it, so
  /// carrying this text as the label made the column wider than the 450pt
  /// sheet: labels were clipped off the left edge and every field was cut off
  /// on the right. Keep the label a short constant and vary only the
  /// placeholder, exactly as the Base URL field above does.
  private func apiKeyPrompt(for kind: ProviderKind) -> String {
    if kind == .ollama {
      return editingProvider == nil
        ? "Optional, not needed for a local service"
        : "Optional, leave empty to keep current"
    }
    return editingProvider == nil ? "" : "Leave empty to keep current"
  }

  private func kindLabel(_ kind: ProviderKind) -> String {
    switch kind {
    case .openAICompatible: return "OpenAI-compatible"
    case .gemini: return "Gemini"
    case .anthropic: return "Anthropic"
    case .ollama: return "Ollama"
    }
  }

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack {
      HStack {
        Text("AI Providers")
          .font(.headline)
        Spacer()
        Button(action: {
          prepareAddForm()
        }) {
          Label("Add Provider", systemImage: "plus")
        }
      }
      .padding(.bottom, 5)

      List {
        ForEach(viewModel.providers, id: \.id) { provider in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(provider.id)
                  .font(.system(.body, design: .monospaced))
                  .fontWeight(.bold)
                Text(kindLabel(provider.kind))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              if let baseURL = provider.baseURL {
                Text(baseURL.absoluteString)
                  .font(.caption)
                  .foregroundColor(.secondary)
              } else {
                Text("Default Endpoint")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
              Text("Model: \(provider.defaultModel)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            Button("Edit") {
              prepareEditForm(provider)
            }
            Button("Delete") {
              deleteProvider(provider.id)
            }
            .foregroundColor(.red)
          }
          .padding(.vertical, 4)
        }
      }
      .listStyle(PlainListStyle())
    }
    .sheet(isPresented: $isShowingEditSheet) {
      VStack(spacing: 0) {
        Text(editingProvider == nil ? "Add AI Provider" : "Edit AI Provider")
          .font(.headline)
          .padding()

        Form {
          Section {
            TextField("Name", text: $name)
              .disabled(editingProvider != nil)

            Picker("Kind", selection: $kind) {
              ForEach(selectableKinds, id: \.self) { kind in
                Text(kindLabel(kind)).tag(kind)
              }
            }

            TextField(
              "Base URL", text: $baseURLString,
              prompt: Text(baseURLPlaceholder(for: kind)))

            TextField("Default Model", text: $defaultModel)

            HStack {
              Text("Timeout")
              Slider(value: $timeout, in: 5...300, step: 5)
              Text("\(Int(timeout))s")
            }

            HStack {
              Text("Retry delay")
              Slider(value: $retryDelay, in: 0...5, step: 0.5)
              Text(String(format: "%.1fs", retryDelay))
            }
            .help(
              "Pause before the single automatic retry of a failed request. "
                + "Only transient failures (network errors, timeouts, rate limits, "
                + "server errors) are retried. Set to 0 to retry immediately.")

            SecureField(
              "API Key", text: $apiKey,
              prompt: Text(apiKeyPrompt(for: kind)))
          }
        }
        .padding()

        if let errorMessage = errorMessage {
          Text(errorMessage)
            .foregroundColor(.red)
            .font(.caption)
            .padding(.horizontal)
        }

        HStack {
          Button("Cancel") {
            isShowingEditSheet = false
          }
          Spacer()
          Button("Save") {
            saveProvider()
          }
        }
        .padding()
      }
      .frame(width: 450, height: 350)
    }
  }

  private func prepareAddForm() {
    editingProvider = nil
    name = ""
    kind = .openAICompatible
    baseURLString = ""
    defaultModel = ""
    timeout = 30.0
    retryDelay = ProviderConfig.defaultRetryDelaySeconds
    apiKey = ""
    errorMessage = nil
    isShowingEditSheet = true
  }

  private func prepareEditForm(_ provider: ProviderConfig) {
    editingProvider = provider
    name = provider.id
    kind = provider.kind
    baseURLString = provider.baseURL?.absoluteString ?? ""
    defaultModel = provider.defaultModel
    timeout = provider.timeoutSeconds
    // Loaded unclamped, matching `timeout` above. Clamping here would rewrite a
    // hand-edited out-of-range value to the slider's ceiling on the next save,
    // silently discarding a setting the user chose on purpose.
    retryDelay = provider.retryDelaySeconds
    apiKey = ""
    errorMessage = nil
    isShowingEditSheet = true
  }

  private func saveProvider() {
    do {
      try viewModel.saveProvider(
        id: editingProvider?.id,
        name: name,
        kind: kind,
        baseURLString: baseURLString,
        defaultModel: defaultModel,
        timeout: timeout,
        retryDelay: retryDelay,
        apiKey: apiKey
      )
      isShowingEditSheet = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func deleteProvider(_ id: String) {
    do {
      try viewModel.deleteProvider(id: id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
