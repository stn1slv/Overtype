import KeyboardShortcuts
import SwiftUI

public struct ActionsTab: View {
  @ObservedObject var viewModel: SettingsViewModel

  @State private var editingAction: ActionConfig? = nil
  @State private var isShowingEditSheet = false

  // Form fields
  @State private var title = ""
  @State private var enabled = true
  @State private var providerID = ""
  @State private var modelOverride = ""
  @State private var systemPrompt = ""
  @State private var userPromptTemplate = "{{text}}"
  @State private var temperature = 0.0
  @State private var maxInputCharacters = 5000
  @State private var allowNewlines = false
  @State private var writeStrategy: WriteStrategy = .typing
  @State private var errorMessage: String? = nil

  // Recording target name
  @State private var recorderName: KeyboardShortcuts.Name = KeyboardShortcuts.Name(
    "_temp_action_shortcut")

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    VStack {
      HStack {
        Text("Actions (Automations)")
          .font(.headline)
        Spacer()
        Button(action: {
          prepareAddForm()
        }) {
          Label("Add Action", systemImage: "plus")
        }
      }
      .padding(.bottom, 5)

      List {
        ForEach(viewModel.actions, id: \.id) { action in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(action.title)
                  .fontWeight(.semibold)
                Text("(\(action.id))")
                  .font(.system(.caption, design: .monospaced))
                  .foregroundColor(.secondary)
              }
              Text("Provider: \(action.providerID)")
                .font(.caption)
                .foregroundColor(.secondary)
              if let shortcut = action.shortcut {
                Text("Shortcut: \(shortcut.displayString)")
                  .font(.caption)
                  .foregroundColor(.blue)
              } else {
                Text("No shortcut assigned")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
            Spacer()

            Toggle(
              "",
              isOn: Binding(
                get: { action.enabled },
                set: { _ in toggleAction(action.id) }
              )
            )
            .toggleStyle(SwitchToggleStyle())

            Button("Edit") {
              prepareEditForm(action)
            }

            Button("Delete") {
              deleteAction(action.id)
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
        Text(editingAction == nil ? "Add Action" : "Edit Action")
          .font(.headline)
          .padding()

        Form {
          ScrollView {
            VStack(alignment: .leading, spacing: 10) {
              TextField("Title", text: $title)
                .disabled(editingAction != nil)

              Toggle("Enabled", isOn: $enabled)

              Picker("Provider", selection: $providerID) {
                ForEach(viewModel.providers, id: \.id) { provider in
                  Text(provider.id).tag(provider.id)
                }
              }

              TextField(
                "Model Override (Optional)", text: $modelOverride, prompt: Text("e.g. gpt-4o"))

              Text("System Prompt")
                .font(.caption)
                .foregroundColor(.secondary)
              TextEditor(text: $systemPrompt)
                .frame(height: 80)
                .border(Color.secondary.opacity(0.2))

              TextField("User Prompt Template", text: $userPromptTemplate)

              HStack {
                Text("Temperature: \(String(format: "%.1f", temperature))")
                Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
              }

              HStack {
                Text("Max Characters: \(maxInputCharacters)")
                Slider(
                  value: Binding(
                    get: { Double(maxInputCharacters) },
                    set: { maxInputCharacters = Int($0) }
                  ), in: 500...20000, step: 500)
              }

              Toggle("Allow Newlines", isOn: $allowNewlines)

              Picker("Write Strategy", selection: $writeStrategy) {
                Text("typing").tag(WriteStrategy.typing)
              }

              HStack {
                Text("Global Shortcut")
                Spacer()
                KeyboardShortcuts.Recorder(for: recorderName)
              }
              .padding(.top, 5)
            }
            .padding(.horizontal, 5)
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
            cancelForm()
          }
          Spacer()
          Button("Save") {
            saveAction()
          }
        }
        .padding()
      }
      .frame(width: 480, height: 500)
    }
  }

  private func prepareAddForm() {
    editingAction = nil
    title = ""
    enabled = true
    // Default to first provider
    providerID = viewModel.providers.first?.id ?? "openai"
    modelOverride = ""
    systemPrompt = ""
    userPromptTemplate = "{{text}}"
    temperature = 0.0
    maxInputCharacters = 5000
    allowNewlines = false
    writeStrategy = .typing
    errorMessage = nil

    // Reset the temp recorder shortcut
    recorderName = KeyboardShortcuts.Name("_temp_action_shortcut")
    KeyboardShortcuts.setShortcut(nil, for: recorderName)

    isShowingEditSheet = true
  }

  private func prepareEditForm(_ action: ActionConfig) {
    editingAction = action
    title = action.title
    enabled = action.enabled
    providerID = action.providerID
    modelOverride = action.model ?? ""
    systemPrompt = action.systemPrompt
    userPromptTemplate = action.userPromptTemplate
    temperature = action.temperature
    maxInputCharacters = action.maxInputCharacters
    allowNewlines = action.allowNewlines
    writeStrategy = action.writeStrategy
    errorMessage = nil

    // Bind the recorder directly to the existing action ID
    recorderName = KeyboardShortcuts.Name(action.id)
    isShowingEditSheet = true
  }

  private func cancelForm() {
    if editingAction == nil {
      KeyboardShortcuts.setShortcut(nil, for: recorderName)
    }
    isShowingEditSheet = false
  }

  private func saveAction() {
    var actionShortcut: ActionShortcut? = nil

    // Retrieve recorded shortcut from KeyboardShortcuts
    if let shortcut = KeyboardShortcuts.getShortcut(for: recorderName) {
      actionShortcut = ActionShortcut(
        keyCode: shortcut.key?.rawValue ?? 0,
        modifiers: Int(shortcut.modifiers.rawValue),
        displayString: shortcut.description
      )
    }

    do {
      let existingId = editingAction?.id

      // Save the action via view model and get assigned action ID
      let finalID = try viewModel.saveAction(
        id: existingId,
        title: title,
        enabled: enabled,
        shortcut: actionShortcut,
        providerID: providerID,
        modelOverride: modelOverride,
        systemPrompt: systemPrompt,
        userPromptTemplate: userPromptTemplate,
        temperature: temperature,
        maxInputCharacters: maxInputCharacters,
        allowNewlines: allowNewlines,
        writeStrategy: writeStrategy
      )

      // If creating new action, transfer shortcut from temp to final ID in KeyboardShortcuts
      if existingId == nil, let shortcut = KeyboardShortcuts.getShortcut(for: recorderName) {
        let finalName = KeyboardShortcuts.Name(finalID)
        KeyboardShortcuts.setShortcut(shortcut, for: finalName)
        // Clear the temp recorder shortcut
        KeyboardShortcuts.setShortcut(nil, for: recorderName)
      }

      isShowingEditSheet = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func deleteAction(_ id: String) {
    do {
      try viewModel.deleteAction(id: id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func toggleAction(_ id: String) {
    do {
      try viewModel.toggleActionEnabled(id: id)
    } catch {
      errorMessage = error.localizedDescription
      // Trigger UI update in case the toggle should revert
      viewModel.reloadFromDisk()
    }
  }
}
