import Foundation
import ServiceManagement

/// Keeps ClipSave in the menu bar until the user chooses Quit.
///
/// A small launchd agent bundled in the app (`Support/som.ClipSave.keepalive.plist`)
/// wakes every few seconds and reopens ClipSave if it is not running, unless
/// the user quit it from the menu during the current boot. Anything else that
/// ends the process — a crash, macOS reclaiming memory, a full disk — leaves
/// no marker, so the agent brings the app back.
///
/// The marker holds the boot time rather than a bare flag so that a Quit does
/// not outlive a restart: after the Mac restarts, the app is started again
/// by the login item as usual.
enum KeepAlive {
    nonisolated static let agentPlistName = "som.ClipSave.keepalive.plist"

    private static var agent: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    nonisolated static var defaultMarkerURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipSave", isDirectory: true)
            .appendingPathComponent("user-quit")
    }

    /// Seconds since the epoch at which this boot began, as the agent reads it.
    nonisolated static var bootTimeSeconds: Int? {
        var value = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return nil }
        return Int(value.tv_sec)
    }

    /// Called only from the explicit Quit command.
    nonisolated static func markUserQuit(at url: URL = defaultMarkerURL,
                                         bootTime: Int? = bootTimeSeconds) {
        guard let bootTime else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? String(bootTime).write(to: url, atomically: true, encoding: .utf8)
    }

    nonisolated static func clearUserQuit(at url: URL = defaultMarkerURL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func userQuitThisBoot(at url: URL = defaultMarkerURL,
                                             bootTime: Int? = bootTimeSeconds) -> Bool {
        guard let bootTime,
              let stored = try? String(contentsOf: url, encoding: .utf8)
        else { return false }
        return stored.trimmingCharacters(in: .whitespacesAndNewlines) == String(bootTime)
    }

    /// The agent only reopens `/Applications/ClipSave.app`, so registering it
    /// for a copy running from a disk image or Downloads would be pointless.
    static var isInApplicationsFolder: Bool {
        let path = Bundle.main.bundleURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    static var status: SMAppService.Status { agent.status }

    static var needsApproval: Bool { agent.status == .requiresApproval }

    /// Registers the agent. Safe to call repeatedly.
    @discardableResult
    static func register() -> Bool {
        guard agent.status != .enabled else { return true }
        do {
            try agent.register()
            return agent.status == .enabled
        } catch {
            return false
        }
    }

    static func unregister() {
        guard agent.status != .notRegistered else { return }
        try? agent.unregister()
    }
}
