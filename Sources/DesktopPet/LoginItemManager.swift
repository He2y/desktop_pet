import AppKit
import ServiceManagement

enum LoginItemManager {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var menuTitle: String {
        switch status {
        case .enabled:
            "Launch at Login"
        case .requiresApproval:
            "Launch at Login (Needs Approval)"
        case .notFound:
            "Launch at Login (Unavailable)"
        case .notRegistered:
            "Launch at Login"
        @unknown default:
            "Launch at Login"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status == .enabled || status == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
