import Foundation

extension Notification.Name {
  /// Posted after the configuration was saved, or when hotkey state needs a
  /// config-driven re-registration pass. Observed by AppDelegate, which reloads
  /// providers and re-registers all action hotkeys from the current config.
  public static let overtypeConfigDidChange = Notification.Name("OvertypeConfigDidChange")

  /// Posted by the engine when a run finds the Accessibility permission gone
  /// (finding H4). Observed by AppDelegate, which starts the trust poll so the
  /// Escape monitors are reinstalled automatically once trust returns.
  public static let overtypeAccessibilityTrustLost = Notification.Name(
    "OvertypeAccessibilityTrustLost")
}

public protocol ConfigStoring {
  var config: AppConfig { get }
  func reload() throws
  func save(_ newConfig: AppConfig) throws
}

public class ConfigStore: ConfigStoring {
  public static let shared = ConfigStore()

  private let configURL: URL
  private var currentConfig: AppConfig

  /// Set when the config file existed but could not be decoded at launch. The
  /// app delegate surfaces it to the user (no silent failure); the unreadable
  /// file itself is preserved next to config.json before defaults take over.
  public private(set) var loadFailureMessage: String?

  /// Set when the config file decoded, but some values were dropped or replaced
  /// by defaults by the tolerant decoder (finding C3). Surfaced once at launch
  /// by the app delegate; the issue text names keys and ids only, never values.
  public private(set) var loadWarningMessage: String?

  public var config: AppConfig {
    return currentConfig
  }

  private init() {
    let fileManager = FileManager.default
    let appSupportURL =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
        "Library/Application Support")
    let appDirectory = appSupportURL.appendingPathComponent("Overtype")

    if !fileManager.fileExists(atPath: appDirectory.path) {
      try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    }

    configURL = appDirectory.appendingPathComponent("config.json")

    if !fileManager.fileExists(atPath: configURL.path) {
      try? DefaultConfig.defaultConfigJSON.write(to: configURL, atomically: true, encoding: .utf8)
    }

    do {
      let data = try Data(contentsOf: configURL)
      let issues = ConfigDecodingIssues()
      let decoder = JSONDecoder()
      ConfigDecodingIssues.attach(issues, to: decoder)
      currentConfig = try decoder.decode(AppConfig.self, from: data)
      if !issues.issues.isEmpty {
        for issue in issues.issues {
          Logger.shared.log("Config: \(issue)", level: .warning)
        }
        loadWarningMessage =
          "Some values in config.json could not be read and were ignored or replaced by defaults:\n\n"
          + issues.issues.map { "• \($0)" }.joined(separator: "\n")
          + "\n\nThe file itself was not modified."
      }
    } catch {
      Logger.shared.log("Failed to load config, falling back to default: \(error)", level: .error)
      // Non-destructive fallback: preserve the unreadable file before defaults
      // take over, because the next save would otherwise overwrite the user's
      // hand-edited config with the default one. The message only claims a
      // backup exists when the copy actually succeeded (the file may be
      // missing entirely, e.g. when seeding it failed on a read-only volume).
      var failureMessage =
        "The configuration file could not be read, so the default configuration is in use."
      if fileManager.fileExists(atPath: configURL.path) {
        let backupURL = configURL.deletingLastPathComponent()
          .appendingPathComponent(Self.invalidBackupFileName(for: Date()))
        do {
          try fileManager.copyItem(at: configURL, to: backupURL)
          failureMessage +=
            " The unreadable file was preserved as \(backupURL.lastPathComponent) in the same folder."
        } catch {
          Logger.shared.log("Failed to back up unreadable config: \(error)", level: .error)
        }
      }
      currentConfig = DefaultConfig.defaultConfig ?? DefaultConfig.fallbackConfig
      loadFailureMessage = failureMessage
    }
  }

  /// Name for the preserved copy of an unreadable config file. Pure logic,
  /// unit-tested.
  static func invalidBackupFileName(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "config.json.invalid-\(formatter.string(from: date))"
  }

  public func reload() throws {
    let data = try Data(contentsOf: configURL)
    let issues = ConfigDecodingIssues()
    let decoder = JSONDecoder()
    ConfigDecodingIssues.attach(issues, to: decoder)
    let newConfig = try decoder.decode(AppConfig.self, from: data)
    // Reload is not a launch: issues go to the log only, the one-time launch
    // alert is not re-armed (finding C3).
    for issue in issues.issues {
      Logger.shared.log("Config: \(issue)", level: .warning)
    }
    self.currentConfig = newConfig
    // Debug level: reload now runs on every Settings-window refocus (C7), and
    // an info line per focus change is noise, not signal (review follow-up).
    Logger.shared.log("Configuration reloaded successfully.", level: .debug)
  }

  public func save(_ newConfig: AppConfig) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(newConfig)
    try data.write(to: configURL, options: .atomic)
    self.currentConfig = newConfig
    Logger.shared.log("Configuration saved successfully.", level: .info)
  }
}
