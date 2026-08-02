import SwiftUI

public struct GeneralTab: View {
    @State private var openAIApiKey: String = ""
    @State private var isSaved: Bool = false
    @StateObject private var launchManager = LaunchAtLoginManager()
    
    public init() {}
    
    public var body: some View {
        Form {
            Section(header: Text("Startup")) {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchManager.isEnabled },
                    set: { launchManager.setLaunchAtLogin(enabled: $0) }
                ))
                .toggleStyle(.checkbox)
                
                if let errorMessage = launchManager.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            Section(header: Text("OpenAI Configuration")) {
                SecureField("API Key", text: $openAIApiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button("Save Key to Keychain") {
                        saveKey()
                    }
                    if isSaved {
                        Text("Saved!")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
            }
            
            Section(header: Text("Configuration File")) {
                Button("Open config.json") {
                    let fileManager = FileManager.default
                    if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                        let configURL = appSupportURL.appendingPathComponent("Overtype/config.json")
                        NSWorkspace.shared.open(configURL)
                    }
                }
                Text("Edit this file to manage prompts, models, and shortcuts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            loadKey()
            launchManager.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchManager.refresh()
        }
    }
    
    /// Keychain item that backs the OpenAI provider. Resolved from config so it stays
    /// in sync if the user changes `keychainKey`, instead of a hardcoded literal.
    private var openAIKeychainKey: String {
        let providers = ConfigStore.shared.config.providers
        let provider = providers.first(where: { $0.kind == .openAICompatible })
            ?? providers.first(where: { $0.id == "openai" })
        return provider?.keychainKey ?? "overtype-openai-key"
    }

    private func saveKey() {
        do {
            try KeychainStore.shared.store(key: openAIKeychainKey, value: openAIApiKey)
            isSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isSaved = false
            }
        } catch {
            Logger.shared.log("Failed to save API key", level: .error)
        }
    }

    private func loadKey() {
        if let key = try? KeychainStore.shared.retrieve(key: openAIKeychainKey) {
            openAIApiKey = key
        }
    }
}
