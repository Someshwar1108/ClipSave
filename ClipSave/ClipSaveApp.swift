import SwiftUI
import AppKit
import Carbon.HIToolbox
import Combine
import Sparkle

final class UpdaterModel: ObservableObject {
    static let shared = UpdaterModel()
    @Published var hasPendingUpdate = false
}

@main
struct ClipSaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// `@StateObject`, not `@ObservedObject`.
    ///
    /// `App` is a value type that SwiftUI recreates, and `@ObservedObject`
    /// gives it no stable storage — so every rebuild re-subscribed, and
    /// because the `MenuBarExtra` label below reads this object, each change
    /// invalidated the whole `Scene`. SwiftUI then tore down and rebuilt the
    /// menu bar item, leaking a fresh `NSStatusItem` every time: six of them
    /// after a single launch, with the visible icon belonging to a stale one
    /// whose content was detached, so clicking it did nothing.
    ///
    /// It also churned the `@NSApplicationDelegateAdaptor` instance, which is
    /// what kept blanking `AppDelegate.shared`.
    @StateObject private var updaterModel = UpdaterModel.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView(manager: appDelegate.manager)
                .onAppear {
                    if updaterModel.hasPendingUpdate {
                        appDelegate.updaterController.checkForUpdates(nil)
                    }
                }
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .onAppear { appDelegate.enterForeground(reason: "settings") }
                .onDisappear { appDelegate.exitForeground(reason: "settings") }
        }
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if updaterModel.hasPendingUpdate {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "list.clipboard.fill")
                Circle()
                    .fill(.red)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: -1)
            }
        } else {
            Image(systemName: "list.clipboard.fill")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The live delegate.
    ///
    /// Held **strongly** and assigned from `applicationDidFinishLaunching`,
    /// for two reasons learned the hard way:
    ///
    /// - It used to be `weak` and assigned in `init`. SwiftUI constructs the
    ///   adaptor's type more than once as the `App` struct is re-evaluated, so
    ///   a transient instance overwrote the reference and then nilled it out
    ///   when it deallocated. Every `AppDelegate.shared?` call site silently
    ///   became a no-op, which is what made the shortcut recorder report
    ///   "ClipSave isn't ready yet".
    /// - `NSApp.delegate` is *not* this object. `@NSApplicationDelegateAdaptor`
    ///   installs a `SwiftUI.AppDelegate` that forwards to ours, so casting
    ///   `NSApp.delegate` to this type always fails.
    ///
    /// `applicationDidFinishLaunching` is only sent to the delegate the system
    /// actually installed, so it's the one place that can't capture a
    /// throwaway instance.
    static private(set) var shared: AppDelegate?

    let manager = ClipboardManager.shared
    lazy var updaterController: SPUStandardUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var hotKeyPanel: NSPanel?
    private var foregroundReasons: Set<String> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        _ = updaterController
        AutoPaste.shared.startTrackingFrontmostApp()
        registerHotKeys()
    }

    /// Installs every hotkey handler once, at launch.
    ///
    /// Registering all four here — even the ones with no combination assigned —
    /// means `HotKeyCenter.rebind` always has a handler to reuse, so Settings
    /// can change a shortcut without needing a reference back to this object.
    private func registerHotKeys() {
        let settings = AppSettings.shared
        let center = HotKeyCenter.shared

        center.register(.openPanel, combo: settings.globalShortcut) { [weak self] in
            self?.togglePanel()
        }
        // The stored combination may have been claimed by another app while
        // ClipSave wasn't running; fall back so the panel stays reachable.
        if center.combo(for: .openPanel) == nil,
           center.rebind(.openPanel, to: .defaultCombo) == nil {
            settings.globalShortcut = .defaultCombo
        }

        center.register(.pasteLastClip, combo: settings.pasteLastShortcut) { [weak self] in
            self?.pasteLastClip()
        }
        center.register(.openPermanent, combo: settings.openPermanentShortcut) { [weak self] in
            self?.openPanel(onTab: "perm")
        }
        center.register(.togglePause, combo: settings.togglePauseShortcut) {
            AppSettings.shared.pauseMonitoring.toggle()
        }
    }

    /// Copies the most recent clip and pastes it straight into the frontmost
    /// app, without ever showing the panel.
    private func pasteLastClip() {
        guard let clip = manager.tempClips.first else { return }
        manager.copyBack(clip)
        // We never took focus, so the frontmost app is still the target.
        if AutoPaste.hasAccessibilityPermission {
            AutoPaste.shared.pasteIntoPreviousApp()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The history save is debounced, so without this the last few seconds
        // of clips would be lost on quit.
        manager.flushTemporary()
    }

    /// Shows the panel on a specific tab, rather than toggling it.
    private func openPanel(onTab tab: String) {
        PanelRouter.shared.requestedTab = tab
        let panel = ensurePanel()
        if !panel.isVisible {
            togglePanel()
        }
    }

    /// Promote the app to a regular foreground app (Dock icon, Cmd+Tab).
    /// Each caller passes a unique `reason`; the app stays foreground until
    /// every caller pairs it with `exitForeground(reason:)`. This avoids
    /// races between Settings, Sparkle, and any other UI that wants to be
    /// visible above other apps.
    func enterForeground(reason: String) {
        let work = {
            self.foregroundReasons.insert(reason)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    func exitForeground(reason: String) {
        let work = {
            self.foregroundReasons.remove(reason)
            if self.foregroundReasons.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func togglePanel() {
        let panel = ensurePanel()
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                panel.alphaValue = 1
            })
            return
        }
        positionNearCursor(panel)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func ensurePanel() -> NSPanel {
        if let p = hotKeyPanel { return p }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.hidesOnDeactivate = true
        p.isReleasedWhenClosed = false
        p.appearance = nil // follow system appearance
        let host = NSHostingController(rootView: ContentView(manager: manager))
        p.contentViewController = host
        hotKeyPanel = p
        return p
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin.x = mouse.x - frame.width / 2
        frame.origin.y = mouse.y - frame.height - 10
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        }
        panel.setFrame(frame, display: false)
    }
}

extension AppDelegate: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        enterForeground(reason: "sparkle")
        guard !handleShowingUpdate else { return }
        Task { @MainActor in
            UpdaterModel.shared.hasPendingUpdate = true
        }
    }

    func standardUserDriverWillShowModalAlert() {
        enterForeground(reason: "sparkle")
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in
            UpdaterModel.shared.hasPendingUpdate = false
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            UpdaterModel.shared.hasPendingUpdate = false
        }
        exitForeground(reason: "sparkle")
    }
}
