import SwiftUI

public struct ProvidersTab: View {
  @ObservedObject var viewModel: SettingsViewModel

  @State private var editingProvider: ProviderConfig? = nil
  @State private var isShowingEditSheet = false

  // Form fields
  @State private var name = ""
  @State private var baseURLString = ""
  @State private var defaultModel = ""
  @State private var timeout = 30.0
  @State private var apiKey = ""
  @State private var errorMessage: String? = nil

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
              Text(provider.id)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.bold)
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

            TextField("Base URL", text: $baseURLString, prompt: Text("https://api.openai.com/v1"))

            TextField("Default Model", text: $defaultModel)

            HStack {
              Text("Timeout")
              Slider(value: $timeout, in: 5...300, step: 5)
              Text("\(Int(timeout))s")
            }

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
    baseURLString = ""
    defaultModel = ""
    timeout = 30.0
    apiKey = ""
    errorMessage = nil
    isShowingEditSheet = true
  }

  private func prepareEditForm(_ provider: ProviderConfig) {
    editingProvider = provider
    name = provider.id
    baseURLString = provider.baseURL?.absoluteString ?? ""
    defaultModel = provider.defaultModel
    timeout = provider.timeoutSeconds
    apiKey = ""
    errorMessage = nil
    isShowingEditSheet = true
  }

  private func saveProvider() {
    do {
      try viewModel.saveProvider(
        id: editingProvider?.id,
        name: name,
        baseURLString: baseURLString,
        defaultModel: defaultModel,
        timeout: timeout,
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
