import Foundation

public class ProviderRegistry {
  public static let shared = ProviderRegistry()

  private var providers: [String: AIProvider] = [:]

  private init() {
    reloadProviders()
  }

  public func reloadProviders() {
    providers.removeAll()
    let providerConfigs = ConfigStore.shared.config.providers

    for config in providerConfigs {
      switch config.kind {
      case .openAICompatible:
        providers[config.id] = OpenAICompatibleProvider(config: config)
      case .anthropic:
        providers[config.id] = AnthropicProvider(config: config)
      case .ollama:
        // To be implemented in US3
        break
      case .gemini:
        providers[config.id] = GeminiProvider(config: config)
      }
    }
  }

  public func provider(for id: String) -> AIProvider? {
    return providers[id]
  }
}
