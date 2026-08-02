import Foundation

public struct DefaultConfig {
    
    public static var defaultConfigJSON: String {
        """
        {
          "global": {
            "typingSpeedMultiplier": 1.0,
            "showHUD": true
          },
          "providers": [
            {
              "id": "openai",
              "kind": "openai",
              "baseURL": "https://api.openai.com/v1",
              "defaultModel": "gpt-5.4-nano",
              "timeoutSeconds": 30.0,
              "keychainKey": "overtype-openai-key"
            }
          ],
          "actions": [
            {
              "id": "fix-grammar",
              "title": "Fix grammar",
              "enabled": true,
              "shortcut": { "keyCode": 5, "modifiers": 1835008, "displayString": "⌃⌥⌘G" },
              "providerID": "openai",
              "model": null,
              "systemPrompt": "You are a proofreader. Fix grammar, spelling, and punctuation. Do not change the meaning or tone. Output ONLY the corrected text, no quotes or conversational text.",
              "userPromptTemplate": "{{text}}",
              "temperature": 0.0,
              "maxInputCharacters": 5000,
              "allowNewlines": false,
              "writeStrategy": "typing"
            }
          ]
        }
        """
    }
    
    public static var defaultConfig: AppConfig? {
        guard let data = defaultConfigJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Non-optional last resort used if the embedded JSON ever fails to decode, so the
    /// app still launches (with no actions) instead of crashing on a force-unwrap.
    public static var fallbackConfig: AppConfig {
        AppConfig(global: GeneralConfig(), providers: [], actions: [])
    }
}
