import Foundation

public protocol ConfigStoring {
  var config: AppConfig { get }
  func reload() throws
  func save(_ newConfig: AppConfig) throws
}

public class ConfigStore: ConfigStoring {
  public static let shared = ConfigStore()

  private let configURL: URL
  private var currentConfig: AppConfig

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
      currentConfig = try JSONDecoder().decode(AppConfig.self, from: data)
    } catch {
      Logger.shared.log("Failed to load config, falling back to default: \(error)", level: .error)
      currentConfig = DefaultConfig.defaultConfig ?? DefaultConfig.fallbackConfig
    }
  }

  public func reload() throws {
    let data = try Data(contentsOf: configURL)
    let newConfig = try JSONDecoder().decode(AppConfig.self, from: data)
    self.currentConfig = newConfig
    Logger.shared.log("Configuration reloaded successfully.", level: .info)
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
