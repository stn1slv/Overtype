import SwiftUI

public struct GeneralTab: View {
  @ObservedObject var viewModel: SettingsViewModel
  @StateObject private var launchManager = LaunchAtLoginManager()
  @State private var isSaved = false
  @State private var errorMessage: String? = nil

  // Read from the bundle each time this view struct is initialised, which is
  // cheap and always yields the same value for a given build. Deliberately
  // outside SettingsViewModel and outside @State: the version is read-only
  // information, so it must not become draft state or take part in saving.
  private let versionText = AppVersion.current.displayString

  // Rejects negative cadence values at the field (finding C2). 0 stays allowed:
  // it is the sentinel the bindings map to "unset". TextWriter additionally
  // normalizes whatever reaches it, so hand-edited files are covered too.
  private static let cadenceFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    return formatter
  }()

  public init(viewModel: SettingsViewModel) {
    self.viewModel = viewModel
  }

  public var body: some View {
    Form {
      // A Grid gives one shared, trailing-aligned label column across all these
      // rows. SwiftUI Form auto-sizes label columns per Section, so labels in
      // different sections (e.g. "Startup" vs "Speed Multiplier") never lined up.
      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 12) {
        GridRow {
          Text("Startup")
            .gridColumnAlignment(.trailing)
          Toggle(
            "Launch at login",
            isOn: Binding(
              get: { launchManager.isEnabled },
              set: { launchManager.setLaunchAtLogin(enabled: $0) }
            )
          )
          .toggleStyle(.checkbox)
        }

        if let errorMessage = launchManager.errorMessage {
          GridRow {
            Color.clear.frame(width: 0, height: 0)
            Text(errorMessage)
              .foregroundColor(.red)
              .font(.caption)
          }
        }

        GridRow {
          Text("Global Typing Cadence")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .gridCellColumns(2)
        }

        GridRow {
          Text("Speed Multiplier")
          HStack {
            Slider(value: $viewModel.global.typingSpeedMultiplier, in: 0.1...10.0, step: 0.1)
            Text("\(String(format: "%.1f", viewModel.global.typingSpeedMultiplier))x")
          }
        }

        GridRow {
          Color.clear.frame(width: 0, height: 0)
          Toggle("Show HUD", isOn: $viewModel.global.showHUD)
            .toggleStyle(.checkbox)
            .help("Hides the progress indicator during a run. Errors are always shown.")
        }

        // The row label in the leading Grid column already names each field, so
        // the TextField's own label is hidden; otherwise it renders inside the
        // fixed frame and squeezes the input box to a few characters.
        GridRow {
          Text("Default Chunk Size")
          HStack {
            TextField(
              "Default Chunk Size",
              value: Binding(
                get: { viewModel.global.typingChunkSize ?? 0 },
                set: { viewModel.global.typingChunkSize = $0 == 0 ? nil : $0 }
              ), formatter: Self.cadenceFormatter, prompt: Text("Standard")
            )
            .labelsHidden()
            .frame(width: 100)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Spacer()
          }
        }

        GridRow {
          Text("Default Delay (µs)")
          HStack {
            TextField(
              "Default Delay (µs)",
              value: Binding(
                get: { viewModel.global.typingDelayMicroseconds ?? 0 },
                set: { viewModel.global.typingDelayMicroseconds = $0 == 0 ? nil : $0 }
              ), formatter: Self.cadenceFormatter, prompt: Text("Standard")
            )
            .labelsHidden()
            .frame(width: 100)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            Spacer()
          }
        }
      }

      Section(header: Text("Per-Application Cadence Overrides")) {
        Text("Configure custom typing delays and chunk sizes for specific applications.")
          .font(.caption)
          .foregroundColor(.secondary)

        // Column headers shown once. The per-row TextFields hide their own
        // labels (.labelsHidden) so the fixed field widths are honored instead
        // of collapsing to fit repeated inline labels.
        if !viewModel.appOverridesList.isEmpty {
          HStack {
            Text("Bundle ID").frame(width: 200, alignment: .leading)
            Text("Chunk").frame(width: 60, alignment: .leading)
            Text("Delay (µs)").frame(width: 80, alignment: .leading)
            Spacer()
          }
          .font(.caption)
          .foregroundColor(.secondary)
        }

        ForEach($viewModel.appOverridesList) { $draft in
          HStack {
            TextField(
              "Bundle ID", text: $draft.bundleID,
              prompt: Text("e.g. com.apple.Safari")
            )
            .labelsHidden()
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 200)

            TextField(
              "Chunk",
              value: Binding(
                get: { $draft.chunkSize.wrappedValue ?? 0 },
                set: { $draft.chunkSize.wrappedValue = $0 == 0 ? nil : $0 }
              ), formatter: Self.cadenceFormatter, prompt: Text("Default")
            )
            .labelsHidden()
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 60)

            TextField(
              "Delay (µs)",
              value: Binding(
                get: { $draft.delay.wrappedValue ?? 0 },
                set: { $draft.delay.wrappedValue = $0 == 0 ? nil : $0 }
              ), formatter: Self.cadenceFormatter, prompt: Text("Default")
            )
            .labelsHidden()
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(width: 80)

            Button(action: {
              viewModel.appOverridesList.removeAll { $0.id == draft.id }
            }) {
              Image(systemName: "trash")
            }
            .buttonStyle(BorderlessButtonStyle())
            .foregroundColor(.red)

            Spacer()
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

      // LabeledContent rather than a hand-built HStack: it lets a long value
      // wrap instead of truncating, and exposes the label and value to VoiceOver
      // as one associated element. It does NOT align this label with the Grid
      // above: as the comment on that Grid says, Form sizes label columns per
      // Section, and this row is its own Section.
      Section {
        LabeledContent("Version") {
          // Selectable so it can be pasted into a bug report. No pasteboard code
          // of ours is involved: the copy is performed by the system on the
          // user's explicit command, so Constitution Principle I still holds.
          Text(versionText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
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
