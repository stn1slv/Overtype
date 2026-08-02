import Combine
import Foundation

public struct AppOverrideDraft: Identifiable, Equatable {
  public var id: String { bundleID }
  public var bundleID: String
  public var chunkSize: Int?
  public var delay: Int?

  public init(bundleID: String, chunkSize: Int?, delay: Int?) {
    self.bundleID = bundleID
    self.chunkSize = chunkSize
    self.delay = delay
  }
}

public final class SettingsViewModel: ObservableObject {
  @Published public var global: GeneralConfig
  @Published public var providers: [ProviderConfig]
  @Published public var actions: [ActionConfig]
  @Published public var appOverridesList: [AppOverrideDraft]

  public init() {
    let config = ConfigStore.shared.config
    self.global = config.global
    self.providers = config.providers
    self.actions = config.actions
    self.appOverridesList = (config.global.appTypingOverrides ?? [:]).map {
      AppOverrideDraft(
        bundleID: $0.key, chunkSize: $0.value.typingChunkSize,
        delay: $0.value.typingDelayMicroseconds)
    }.sorted { $0.bundleID < $1.bundleID }
  }

  public func reloadFromDisk() {
    let config = ConfigStore.shared.config
    self.global = config.global
    self.providers = config.providers
    self.actions = config.actions
    self.appOverridesList = (config.global.appTypingOverrides ?? [:]).map {
      AppOverrideDraft(
        bundleID: $0.key, chunkSize: $0.value.typingChunkSize,
        delay: $0.value.typingDelayMicroseconds)
    }.sorted { $0.bundleID < $1.bundleID }
  }

  public func saveSettings() throws {
    // Map draft overrides list back to dictionary
    var overridesDict: [String: AppTypingOverride] = [:]
    var seenBundleIDs = Set<String>()
    for draft in appOverridesList {
      let trimmedBundleID = draft.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedBundleID.isEmpty else {
        continue
      }
      if seenBundleIDs.contains(trimmedBundleID) {
        throw NSError(
          domain: "SettingsError", code: 20,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Duplicate per-application override for bundle ID '\(trimmedBundleID)'. Please combine them into a single entry."
          ])
      }
      seenBundleIDs.insert(trimmedBundleID)
      overridesDict[trimmedBundleID] = AppTypingOverride(
        typingChunkSize: draft.chunkSize,
        typingDelayMicroseconds: draft.delay
      )
    }

    var updatedGlobal = global
    updatedGlobal.appTypingOverrides = overridesDict.isEmpty ? nil : overridesDict

    let newConfig = AppConfig(
      global: updatedGlobal,
      providers: providers,
      actions: actions
    )

    try ConfigStore.shared.save(newConfig)

    // Notify application delegate to reload hotkeys dynamically
    NotificationCenter.default.post(name: Notification.Name("OvertypeConfigDidChange"), object: nil)
  }

  // MARK: - Providers Management

  public func saveProvider(
    id: String?, name: String, baseURLString: String, defaultModel: String, timeout: Double,
    apiKey: String
  ) throws {
    // Validation
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedModel = defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      throw NSError(
        domain: "SettingsError", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Provider name cannot be empty."])
    }
    guard !trimmedModel.isEmpty else {
      throw NSError(
        domain: "SettingsError", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Default model cannot be empty."])
    }

    let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    let url: URL?
    if !trimmedBaseURL.isEmpty {
      guard let parsedURL = URL(string: trimmedBaseURL), parsedURL.scheme != nil else {
        throw NSError(
          domain: "SettingsError", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL."])
      }
      url = parsedURL
    } else {
      url = nil
    }

    if let existingId = id {
      // Edit mode
      if let index = providers.firstIndex(where: { $0.id == existingId }) {
        var provider = providers[index]
        provider.baseURL = url
        provider.defaultModel = trimmedModel
        provider.timeoutSeconds = timeout
        providers[index] = provider

        // Save API Key if provided
        if !apiKey.isEmpty {
          let keychainKey = provider.keychainKey ?? "overtype-\(existingId)-key"
          providers[index].keychainKey = keychainKey
          try KeychainStore.shared.store(key: keychainKey, value: apiKey)
        }
      }
    } else {
      // Create mode
      let existingIDs = providers.map { $0.id }
      let slug = uniqueSlug(for: trimmedName, existingIDs: existingIDs)
      let keychainKey = "overtype-\(slug)-key"

      // Save API Key
      if !apiKey.isEmpty {
        try KeychainStore.shared.store(key: keychainKey, value: apiKey)
      }

      let newProvider = ProviderConfig(
        id: slug,
        kind: .openAICompatible,
        baseURL: url,
        defaultModel: trimmedModel,
        timeoutSeconds: timeout,
        keychainKey: keychainKey
      )
      providers.append(newProvider)
    }

    try saveSettings()
  }

  public func deleteProvider(id: String) throws {
    if let index = providers.firstIndex(where: { $0.id == id }) {
      let provider = providers[index]
      if let keychainKey = provider.keychainKey {
        try? KeychainStore.shared.delete(key: keychainKey)
      }
      providers.remove(at: index)

      // Disable actions referencing the deleted provider
      for actionIndex in actions.indices {
        if actions[actionIndex].providerID == id {
          actions[actionIndex].enabled = false
        }
      }

      try saveSettings()
    }
  }

  // MARK: - Actions Management

  @discardableResult
  public func saveAction(
    id: String?,
    title: String,
    enabled: Bool,
    shortcut: ActionShortcut?,
    providerID: String,
    modelOverride: String?,
    systemPrompt: String,
    userPromptTemplate: String,
    temperature: Double,
    maxInputCharacters: Int,
    allowNewlines: Bool,
    writeStrategy: WriteStrategy
  ) throws -> String {
    // Validation
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedUserTemplate = userPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedTitle.isEmpty else {
      throw NSError(
        domain: "SettingsError", code: 10,
        userInfo: [NSLocalizedDescriptionKey: "Action title cannot be empty."])
    }
    guard !trimmedSystem.isEmpty else {
      throw NSError(
        domain: "SettingsError", code: 11,
        userInfo: [NSLocalizedDescriptionKey: "System prompt cannot be empty."])
    }
    guard trimmedUserTemplate.contains("{{text}}") else {
      throw NSError(
        domain: "SettingsError", code: 12,
        userInfo: [
          NSLocalizedDescriptionKey: "User prompt template must contain the '{{text}}' placeholder."
        ])
    }
    guard temperature >= 0.0 && temperature <= 2.0 else {
      throw NSError(
        domain: "SettingsError", code: 13,
        userInfo: [NSLocalizedDescriptionKey: "Temperature must be between 0.0 and 2.0."])
    }
    guard maxInputCharacters > 0 else {
      throw NSError(
        domain: "SettingsError", code: 14,
        userInfo: [NSLocalizedDescriptionKey: "Maximum input characters must be positive."])
    }

    // Shortcut conflict checking
    if enabled, let newShortcut = shortcut {
      let conflict = actions.first { action in
        action.id != id && action.enabled && action.shortcut?.keyCode == newShortcut.keyCode
          && action.shortcut?.modifiers == newShortcut.modifiers
      }
      if let conflictingAction = conflict {
        throw NSError(
          domain: "SettingsError", code: 15,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Shortcut conflict: Already in use by '\(conflictingAction.title)'."
          ])
      }
    }

    let finalModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = (finalModel?.isEmpty ?? true) ? nil : finalModel

    let finalID: String
    if let existingId = id {
      finalID = existingId
      // Edit mode
      if let index = actions.firstIndex(where: { $0.id == existingId }) {
        actions[index] = ActionConfig(
          id: existingId,
          title: trimmedTitle,
          enabled: enabled,
          shortcut: shortcut,
          providerID: providerID,
          model: model,
          systemPrompt: trimmedSystem,
          userPromptTemplate: trimmedUserTemplate,
          temperature: temperature,
          maxInputCharacters: maxInputCharacters,
          allowNewlines: allowNewlines,
          writeStrategy: writeStrategy
        )
      }
    } else {
      // Create mode
      let existingIDs = actions.map { $0.id }
      finalID = uniqueSlug(for: trimmedTitle, existingIDs: existingIDs)

      let newAction = ActionConfig(
        id: finalID,
        title: trimmedTitle,
        enabled: enabled,
        shortcut: shortcut,
        providerID: providerID,
        model: model,
        systemPrompt: trimmedSystem,
        userPromptTemplate: trimmedUserTemplate,
        temperature: temperature,
        maxInputCharacters: maxInputCharacters,
        allowNewlines: allowNewlines,
        writeStrategy: writeStrategy
      )
      actions.append(newAction)
    }

    try saveSettings()
    return finalID
  }

  public func deleteAction(id: String) throws {
    if let index = actions.firstIndex(where: { $0.id == id }) {
      actions.remove(at: index)
      try saveSettings()
    }
  }

  public func toggleActionEnabled(id: String) throws {
    if let index = actions.firstIndex(where: { $0.id == id }) {
      let targetAction = actions[index]

      // If enabling, check for hotkey conflict
      if !targetAction.enabled, let newShortcut = targetAction.shortcut {
        let conflict = actions.first { action in
          action.id != id && action.enabled && action.shortcut?.keyCode == newShortcut.keyCode
            && action.shortcut?.modifiers == newShortcut.modifiers
        }
        if let conflictingAction = conflict {
          throw NSError(
            domain: "SettingsError", code: 16,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Shortcut conflict: Already in use by '\(conflictingAction.title)'."
            ])
        }
      }

      actions[index].enabled.toggle()
      try saveSettings()
    }
  }

  // MARK: - Helper Slug Generation & Deduplication

  public func toSlug(_ title: String) -> String {
    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
    let filtered = title.unicodeScalars.filter { allowedCharacters.contains($0) }
    let trimmed = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let slug = trimmed.replacingOccurrences(of: " ", with: "-")
      .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
    return slug
  }

  public func uniqueSlug(for title: String, existingIDs: [String]) -> String {
    let base = toSlug(title)
    let baseSlug = base.isEmpty ? "unnamed" : base
    if !existingIDs.contains(baseSlug) {
      return baseSlug
    }
    var suffix = 1
    while existingIDs.contains("\(baseSlug)-\(suffix)") {
      suffix += 1
    }
    return "\(baseSlug)-\(suffix)"
  }
}
