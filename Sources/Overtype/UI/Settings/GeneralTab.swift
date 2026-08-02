import SwiftUI

public struct GeneralTab: View {
  @ObservedObject var viewModel: SettingsViewModel
  @StateObject private var launchManager = LaunchAtLoginManager()
  @State private var isSaved = false
  @State private var errorMessage: String? = nil

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    Form {
      Section(header: Text("Startup")) {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { launchManager.isEnabled },
            set: { launchManager.setLaunchAtLogin(enabled: $0) }
          )
        )
        .toggleStyle(.checkbox)

        if let errorMessage = launchManager.errorMessage {
          Text(errorMessage)
            .foregroundColor(.red)
            .font(.caption)
        }
      }

      Section(header: Text("Global Typing Cadence")) {
        HStack {
          Text("Speed Multiplier")
          Slider(value: $viewModel.global.typingSpeedMultiplier, in: 0.1...10.0, step: 0.1)
          Text("\(String(format: "%.1f", viewModel.global.typingSpeedMultiplier))x")
        }

        Toggle("Show HUD", isOn: $viewModel.global.showHUD)
          .toggleStyle(.checkbox)

        HStack {
          Text("Default Chunk Size")
          TextField(
            "Default",
            value: Binding(
              get: { viewModel.global.typingChunkSize ?? 0 },
              set: { viewModel.global.typingChunkSize = $0 == 0 ? nil : $0 }
            ), formatter: NumberFormatter(), prompt: Text("Standard")
          )
          .frame(width: 80)
          .textFieldStyle(RoundedBorderTextFieldStyle())
        }

        HStack {
          Text("Default Delay (µs)")
          TextField(
            "Default",
            value: Binding(
              get: { viewModel.global.typingDelayMicroseconds ?? 0 },
              set: { viewModel.global.typingDelayMicroseconds = $0 == 0 ? nil : $0 }
            ), formatter: NumberFormatter(), prompt: Text("Standard")
          )
          .frame(width: 80)
          .textFieldStyle(RoundedBorderTextFieldStyle())
        }
      }

      Section(header: Text("Per-Application Cadence Overrides")) {
        Text("Configure custom typing delays and chunk sizes for specific applications.")
          .font(.caption)
          .foregroundColor(.secondary)

        ForEach(viewModel.appOverridesList.indices, id: \.self) { index in
          HStack {
            TextField(
              "Bundle ID", text: $viewModel.appOverridesList[index].bundleID,
              prompt: Text("e.g. com.apple.Safari")
            )
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 200)

            TextField(
              "Chunk",
              value: Binding(
                get: { viewModel.appOverridesList[index].chunkSize ?? 0 },
                set: { viewModel.appOverridesList[index].chunkSize = $0 == 0 ? nil : $0 }
              ), formatter: NumberFormatter(), prompt: Text("Default")
            )
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 60)

            TextField(
              "Delay (µs)",
              value: Binding(
                get: { viewModel.appOverridesList[index].delay ?? 0 },
                set: { viewModel.appOverridesList[index].delay = $0 == 0 ? nil : $0 }
              ), formatter: NumberFormatter(), prompt: Text("Default")
            )
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 80)

            Button(action: {
              viewModel.appOverridesList.remove(at: index)
            }) {
              Image(systemName: "trash")
            }
            .buttonStyle(BorderlessButtonStyle())
            .foregroundColor(.red)
          }
        }

        Button(action: {
          viewModel.appOverridesList.append(
            AppOverrideDraft(bundleID: "", chunkSize: nil, delay: nil))
        }) {
          Label("Add Override", systemImage: "plus")
        }
      }

      Section {
        HStack {
          Button("Save Preferences") {
            savePreferences()
          }
          if isSaved {
            Text("Saved!")
              .foregroundColor(.green)
              .font(.caption)
          }
          if let error = errorMessage {
            Text(error)
              .foregroundColor(.red)
              .font(.caption)
          }
        }
      }
    }
    .padding()
    .onAppear {
      launchManager.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      launchManager.refresh()
    }
  }

  private func savePreferences() {
    do {
      try viewModel.saveSettings()
      isSaved = true
      errorMessage = nil
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        isSaved = false
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
