import SwiftUI

public struct GeneralTab: View {
    @State private var openAIApiKey: String = ""
    @State private var isSaved: Bool = false
    
    public init() {}
    
    public var body: some View {
        Form {
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
        }
    }
    
    private func saveKey() {
        do {
            try KeychainStore.shared.store(key: "overtype-openai-key", value: openAIApiKey)
            isSaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isSaved = false
            }
        } catch {
            Logger.shared.log("Failed to save API key", level: .error)
        }
    }
    
    private func loadKey() {
        if let key = try? KeychainStore.shared.retrieve(key: "overtype-openai-key") {
            openAIApiKey = key
        }
    }
}
