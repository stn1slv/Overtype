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
  @State private var retryDelay = 0.5
  @State private var apiKey = ""
  @State private var errorMessage: String? = nil

  /// Kinds selectable in the form. Anthropic and Ollama are unimplemented stubs
  /// in ProviderRegistry and stay hidden; a hand-edited config using one of
  /// them still shows its current kind so editing does not silently change it.
  private var selectableKinds: [ProviderKind] {
    var kinds: [ProviderKind] = [.openAICompatible, .gemini]
    if let current = editingProvider?.kind, !kinds.contains(current) {
      kinds.append(current)
    }
    return kinds
  }

  private func kindLabel(_ kind: ProviderKind) -> String {
    switch kind {
    case .openAICompatible: return "OpenAI-compatible"
    case .gemini: return "Gemini"
    case .anthropic: return "Anthropic (not implemented)"
    case .ollama: return "Ollama (not implemented)"
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
              prompt: Text(
                kind == .gemini
                  ? "Default: generativelanguage.googleapis.com" : "https://api.openai.com/v1"))

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
              editingProvider == nil ? "API Key" : "API Key (Leave empty to keep current)",
              text: $apiKey)
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
    retryDelay = 0.5
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
    // A hand-edited config can hold a value outside the slider's 0...5 range;
    // clamp so the slider shows a truthful position instead of pinning silently.
    retryDelay = min(max(provider.retryDelaySeconds, 0), 5)
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
