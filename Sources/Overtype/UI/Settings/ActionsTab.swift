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

  // The recorder is ALWAYS bound to this temporary name, never to a live
  // action's name: recording takes effect (and Carbon-registers) immediately,
  // so binding to the live name would activate an unsaved shortcut and make
  // Cancel unable to revert it.
  private let recorderName = KeyboardShortcuts.Name("_temp_action_shortcut")

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
    .sheet(isPresented: $isShowingEditSheet, onDismiss: cleanupRecorder) {
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

    // Seed the temp recorder with the action's current shortcut so the form
    // shows it; the live action name is never bound (see recorderName).
    KeyboardShortcuts.setShortcut(action.shortcut?.keyboardShortcut, for: recorderName)
    isShowingEditSheet = true
  }

  private func cancelForm() {
    isShowingEditSheet = false
  }

  /// Runs on EVERY sheet dismissal (Save, Cancel, Esc). QUIRK WORKAROUND
  /// (KeyboardShortcuts 1.15.0): `setShortcut(nil, for:)` Carbon-unregisters by
  /// shortcut VALUE with no reference counting, so clearing the temp name can
  /// also kill a real action's registration when both hold the same combo
  /// (e.g. the seeded shortcut in edit mode). Re-registering everything from
  /// config afterwards makes the config-driven pass the last word, healing any
  /// Carbon state the recorder disturbed.
  private func cleanupRecorder() {
    KeyboardShortcuts.setShortcut(nil, for: recorderName)
    NotificationCenter.default.post(name: .overtypeConfigDidChange, object: nil)
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
      // The saved config is the single source of truth for shortcuts: saving
      // posts OvertypeConfigDidChange, which registers the hotkey under the
      // action's own name, and the sheet's onDismiss cleanup re-runs that pass
      // after clearing the temp recorder. No temp-to-final transfer is needed
      // (doing one used to Carbon-unregister the freshly registered shortcut).
      _ = try viewModel.saveAction(
        id: editingAction?.id,
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
