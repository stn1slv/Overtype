import Foundation
import os

public enum LogLevel {
    case debug, info, warning, error
}

public class Logger {
    public static let shared = Logger()
    
    private let osLog = OSLog(subsystem: "com.example.Overtype", category: "App")
    
    // In production, debug mode should be false to prevent logging sensitive user data.
    public var isDebugEnabled: Bool = false
    
    private init() {}
    
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
        
        // Log to Apple Unified Logging
        os_log("%{public}s", log: self.osLog, type: type, formattedMessage)
        
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
