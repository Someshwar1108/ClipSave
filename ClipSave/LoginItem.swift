import Foundation
import ServiceManagement

/// Launch-at-login, via the main app's own login-item registration.
///
/// `SMAppService.mainApp` needs no helper bundle — the app registers itself —
/// but it does report `.requiresApproval` when the user has previously
/// disabled ClipSave in System Settings, which we have to surface rather than
/// silently fail.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns an error message on failure, or `nil` on success.
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // Registering while already enabled throws, so treat the
                // desired end state as idempotent.
                guard SMAppService.mainApp.status != .enabled else { return nil }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status != .notRegistered else { return nil }
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            if requiresApproval {
                return "Approve ClipSave in System Settings → General → Login Items."
            }
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
