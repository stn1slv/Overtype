import Foundation
import os

public enum LogLevel {
  case debug, info, warning, error
}

public class Logger {
  public static let shared = Logger()

  private let osLog = OSLog(subsystem: "com.github.stn1slv.Overtype", category: "App")

  /// Persistent switch for the debug logging mode (finding H7): before this,
  /// the flag had no setter anywhere, so the documented troubleshooting mode
  /// was unreachable and every `.debug` log line was dead code. Enable with
  ///   defaults write com.github.stn1slv.Overtype OvertypeDebugLogging -bool true
  /// There is deliberately no Settings UI for it. When enabled, selected text
  /// and model output DO reach the unified log, so Principle V requires an
  /// explicit warning: one is logged here and AppDelegate shows a visible
  /// alert at launch.
  public static let debugLoggingDefaultsKey = "OvertypeDebugLogging"

  public var isDebugEnabled: Bool

  private init() {
    isDebugEnabled = UserDefaults.standard.bool(forKey: Logger.debugLoggingDefaultsKey)
    if isDebugEnabled {
      log(
        "Debug logging is ENABLED: selected text and model output will appear in logs. "
          + "Disable with: defaults delete com.github.stn1slv.Overtype "
          + Logger.debugLoggingDefaultsKey,
        level: .warning)
    }
  }

  public func log(_ message: String, level: LogLevel = .info) {
    if level == .debug && !isDebugEnabled { return }

    let type: OSLogType
    let prefix: String

    switch level {
    case .debug:
      type = .debug
      prefix = "[DEBUG]"
    case .info:
      type = .info
      prefix = "[INFO]"
    case .warning:
      type = .default
      prefix = "[WARNING]"
    case .error:
      type = .error
      prefix = "[ERROR]"
    }

    let formattedMessage = "\(prefix) \(message)"

    // Log to Apple Unified Logging. %{public}@, not %{public}s (finding H7): a
    // Swift String bridges to an object for C variadics, so %s read it as a C
    // string pointer and produced garbled unified-log output.
    os_log("%{public}@", log: self.osLog, type: type, formattedMessage)

    // Log to stdout for development
    #if DEBUG
      print(formattedMessage)
    #endif
  }

  /// Sanitizes potentially sensitive text (e.g. replacing it with <redacted>)
  /// unless debug mode is explicitly enabled by the user for troubleshooting.
  public func sanitizedLog(sensitiveText: String, context: String, level: LogLevel = .info) {
    let textToLog = isDebugEnabled ? sensitiveText : "<redacted \(sensitiveText.count) chars>"
    log("\(context): \(textToLog)", level: level)
  }
}
