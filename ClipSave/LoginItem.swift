import Foundation
import ServiceManagement

/// Launch-at-login, via the main app's own login-item registration, plus the
/// keep-alive agent that reopens ClipSave if it is stopped (see `KeepAlive`).
///
/// `SMAppService.mainApp` needs no helper bundle — the app registers itself —
/// but it does report `.requiresApproval` when the user has previously
/// disabled ClipSave in System Settings, which we have to surface rather than
/// silently fail.
@MainActor
enum LoginItem {
    private static let defaultAppliedKey = "loginItemDefaultApplied"

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
                // A copy running from a disk image or Downloads would register
                // a path that stops existing, so refuse it.
                if Bundle.main.bundleURL.path.contains("/AppTranslocation/")
                    || Bundle.main.bundleURL.path.hasPrefix("/Volumes/") {
                    return "Move ClipSave to the Applications folder first, then turn this on."
                }
                // Registering while already enabled throws, so treat the
                // desired end state as idempotent.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                KeepAlive.register()
            } else {
                KeepAlive.unregister()
                if SMAppService.mainApp.status != .notRegistered {
                    try SMAppService.mainApp.unregister()
                }
            }
            return nil
        } catch {
            if requiresApproval {
                return "Approve ClipSave in System Settings → General → Login Items."
            }
            return error.localizedDescription
        }
    }

    /// Turns launch-at-login on the first time an installed copy runs, so the
    /// menu bar icon survives a restart without the user finding the setting.
    ///
    /// Runs once per install. A user who later turns it off stays off, and a
    /// `.requiresApproval` status means they disabled it in System Settings,
    /// which is respected rather than overridden.
    static func enableByDefaultOnce() {
        guard KeepAlive.isInApplicationsFolder else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultAppliedKey) else { return }
        let status = SMAppService.mainApp.status
        // `.requiresApproval` means the user disabled it in System Settings;
        // leave that choice alone. Anything else that isn't already enabled
        // gets a registration attempt.
        guard status != .enabled, status != .requiresApproval else {
            defaults.set(true, forKey: defaultAppliedKey)
            return
        }
        _ = setEnabled(true)
        // Only mark it done once it took, so a failure is retried next launch.
        if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
            defaults.set(true, forKey: defaultAppliedKey)
        }
    }

    /// Installs that already had launch-at-login on before the keep-alive
    /// agent existed pick it up here, on any launch.
    static func ensureKeepAliveIfEnabled() {
        guard KeepAlive.isInApplicationsFolder, isEnabled,
              KeepAlive.status != .enabled, KeepAlive.status != .requiresApproval else { return }
        KeepAlive.register()
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
