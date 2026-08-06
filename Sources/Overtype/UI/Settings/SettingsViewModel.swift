import Combine
import Foundation
import KeyboardShortcuts

public struct AppOverrideDraft: Identifiable, Equatable {
  // Stable identity independent of bundleID: new rows start with an empty,
  // non-unique bundleID, so using bundleID as the id would break SwiftUI's
  // ForEach diffing and could crash on delete.
  public let id: UUID
  public var bundleID: String
  public var chunkSize: Int?
  public var delay: Int?

  public init(id: UUID = UUID(), bundleID: String, chunkSize: Int?, delay: Int?) {
    self.id = id
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
    self.appOverridesList = SettingsViewModel.buildOverridesList(
      from: config, preservingIDsFrom: [])
  }

  public func reloadFromDisk() {
    let config = ConfigStore.shared.config
    let storeOverrides = SettingsViewModel.buildOverridesList(
      from: config, preservingIDsFrom: appOverridesList)
    // This runs on every settings-window refocus. Skip the resync when the user
    // has unsaved in-memory edits, otherwise a half-entered row or unsaved change
    // would be silently discarded when focus briefly leaves and returns.
    //
    // Overrides are compared via the draft list, which catches in-progress rows
    // (including a newly added one whose bundleID is still empty). The rest of
    // the config is compared with appTypingOverrides neutralized on both sides:
    // the draft list already covers overrides, and comparing them here would
    // misread a clean state as edited whenever the stored config represents no
    // overrides as an empty dictionary while the model normalizes it to nil.
    var inMemoryGlobal = global
    var storeGlobal = config.global
    inMemoryGlobal.appTypingOverrides = nil
    storeGlobal.appTypingOverrides = nil
    guard appOverridesList == storeOverrides,
      inMemoryGlobal == storeGlobal,
      providers == config.providers,
      actions == config.actions
    else { return }
    self.global = config.global
    self.providers = config.providers
    self.actions = config.actions
    self.appOverridesList = storeOverrides
  }

  private static func buildOverridesList(
    from config: AppConfig, preservingIDsFrom existing: [AppOverrideDraft]
  ) -> [AppOverrideDraft] {
    var idByBundleID: [String: UUID] = [:]
    for draft in existing where idByBundleID[draft.bundleID] == nil {
      idByBundleID[draft.bundleID] = draft.id
    }
    return (config.global.appTypingOverrides ?? [:]).map { key, value in
      AppOverrideDraft(
        id: idByBundleID[key] ?? UUID(),
        bundleID: key,
        chunkSize: value.typingChunkSize,
        delay: value.typingDelayMicroseconds)
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
    NotificationCenter.default.post(name: .overtypeConfigDidChange, object: nil)
  }

  // MARK: - Providers Management

  public func saveProvider(
    id: String?, name: String, kind: ProviderKind, baseURLString: String, defaultModel: String,
    timeout: Double, retryDelay: Double, apiKey: String
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

    // Fallible Keychain work runs BEFORE any published state is mutated, so a
    // failed store never leaves the in-memory config pointing at a key that
    // was not written.
    if let existingId = id {
      // Edit mode
      if let index = providers.firstIndex(where: { $0.id == existingId }) {
        let original = providers[index]
        var provider = original
        provider.kind = kind
        provider.baseURL = url
        provider.defaultModel = trimmedModel
        provider.timeoutSeconds = timeout
        provider.retryDelaySeconds = retryDelay

        // Changing the kind discards any credential the user did not re-enter.
        //
        // Without this, an empty key field means "keep current" (which is what
        // its prompt says), so switching an OpenAI provider to Ollama and
        // pointing it at a LAN address would send the stored `sk-...` key as a
        // bearer token, in cleartext, to a host the user never gave it to. A
        // credential is issued for one service; it must not follow the record to
        // another.
        //
        // The Keychain deletion cannot be rolled back if the save below fails.
        // That is the safe direction to fail in: the worst case is a credential
        // the user has to re-enter, versus one silently sent somewhere new.
        if original.kind != kind, apiKey.isEmpty {
          if let staleKey = provider.keychainKey {
            try? KeychainStore.shared.delete(key: staleKey)
          }
          provider.keychainKey = nil
        }

        // Save API Key if provided
        if !apiKey.isEmpty {
          let keychainKey = provider.keychainKey ?? "overtype-\(existingId)-key"
          try KeychainStore.shared.store(key: keychainKey, value: apiKey)
          provider.keychainKey = keychainKey
        }
        providers[index] = provider
        do {
          try saveSettings()
        } catch {
          // Keep in-memory state in step with the persisted file. The previous
          // Keychain value cannot be restored; the newly stored key remains.
          providers[index] = original
          throw error
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
        kind: kind,
        baseURL: url,
        defaultModel: trimmedModel,
        timeoutSeconds: timeout,
        retryDelaySeconds: retryDelay,
        keychainKey: keychainKey
      )
      providers.append(newProvider)
      do {
        try saveSettings()
      } catch {
        // Roll back so neither the in-memory list nor the Keychain keeps a
        // provider that was never persisted.
        providers.removeLast()
        if !apiKey.isEmpty {
          try? KeychainStore.shared.delete(key: keychainKey)
        }
        throw error
      }
    }
  }

  public func deleteProvider(id: String) throws {
    if let index = providers.firstIndex(where: { $0.id == id }) {
      let provider = providers[index]
      let previousActions = actions
      providers.remove(at: index)

      // Disable actions referencing the deleted provider
      for actionIndex in actions.indices {
        if actions[actionIndex].providerID == id {
          actions[actionIndex].enabled = false
        }
      }

      do {
        try saveSettings()
      } catch {
        // Keep in-memory state in step with the persisted file.
        providers.insert(provider, at: index)
        actions = previousActions
        throw error
      }

      // Best-effort Keychain cleanup only AFTER the config save succeeded, so
      // a failed save cannot leave a still-configured provider without its key.
      if let keychainKey = provider.keychainKey {
        try? KeychainStore.shared.delete(key: keychainKey)
      }
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
      let removed = actions.remove(at: index)
      do {
        try saveSettings()
      } catch {
        // Keep in-memory state in step with the persisted file.
        actions.insert(removed, at: index)
        throw error
      }
      // Hygiene AFTER a successful save: drop the deleted action's persisted
      // shortcut from the KeyboardShortcuts UserDefaults store so stale entries
      // do not accumulate. setShortcut(nil) Carbon-unregisters by shortcut
      // VALUE (no reference counting), which could also hit a surviving action
      // sharing the combo, so a config-driven re-registration pass runs last.
      KeyboardShortcuts.setShortcut(nil, for: KeyboardShortcuts.Name(id))
      NotificationCenter.default.post(name: .overtypeConfigDidChange, object: nil)
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
