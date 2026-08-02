import Foundation
import Combine
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case requiresApproval
    case registrationFailed(Error)
    case unregistrationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Approval required. Please enable Overtype in macOS System Settings > General > Login Items."
        case .registrationFailed(let error):
            return "Failed to enable launch at login: \(error.localizedDescription)"
        case .unregistrationFailed(let error):
            return "Failed to disable launch at login: \(error.localizedDescription)"
        }
    }
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool
    @Published var error: LaunchAtLoginError?
    
    var errorMessage: String? {
        error?.localizedDescription
    }
    
    init() {
        let status = SMAppService.mainApp.status
        self.isEnabled = status == .enabled || status == .requiresApproval
        self.error = status == .requiresApproval ? .requiresApproval : nil
    }
    
    func refresh() {
        let status = SMAppService.mainApp.status
        self.isEnabled = status == .enabled || status == .requiresApproval
        self.error = status == .requiresApproval ? .requiresApproval : nil
    }
    
    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            
            let currentStatus = SMAppService.mainApp.status
            if enabled && currentStatus == .requiresApproval {
                self.error = .requiresApproval
                self.isEnabled = true
            } else {
                self.error = nil
                self.isEnabled = currentStatus == .enabled || currentStatus == .requiresApproval
            }
        } catch {
            self.error = enabled ? .registrationFailed(error) : .unregistrationFailed(error)
            let status = SMAppService.mainApp.status
            self.isEnabled = status == .enabled || status == .requiresApproval
        }
    }
}
