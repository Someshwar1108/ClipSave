import SwiftUI
import AppKit
import Combine
import Sparkle

// --- SETTINGS ---
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let tempCapacity = "tempCapacity"
        static let expirySeconds = "expirySeconds"
        static let maxImageMB = "maxImageMB"
        static let captureText = "captureText"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let captureRichText = "captureRichText"
        static let pauseMonitoring = "pauseMonitoring"
        static let autoPaste = "autoPaste"
        static let watchDesktopScreenshots = "watchDesktopScreenshots"
        static let persistTempClips = "persistTempClips"
        static let globalShortcut = "globalShortcut"
        static let pasteLastShortcut = "pasteLastShortcut"
        static let openPermanentShortcut = "openPermanentShortcut"
        static let togglePauseShortcut = "togglePauseShortcut"
        static let panelShortcuts = "panelShortcuts"
    }

    static let neverExpire: TimeInterval = .greatestFiniteMagnitude

    @Published var tempCapacity: Int { didSet { UserDefaults.standard.set(tempCapacity, forKey: Keys.tempCapacity) } }
    @Published var expirySeconds: TimeInterval { didSet { UserDefaults.standard.set(expirySeconds, forKey: Keys.expirySeconds) } }
    @Published var maxImageMB: Int { didSet { UserDefaults.standard.set(maxImageMB, forKey: Keys.maxImageMB) } }
    @Published var captureText: Bool { didSet { UserDefaults.standard.set(captureText, forKey: Keys.captureText) } }
    @Published var captureImages: Bool { didSet { UserDefaults.standard.set(captureImages, forKey: Keys.captureImages) } }
    @Published var captureFiles: Bool { didSet { UserDefaults.standard.set(captureFiles, forKey: Keys.captureFiles) } }
    @Published var captureRichText: Bool { didSet { UserDefaults.standard.set(captureRichText, forKey: Keys.captureRichText) } }
    @Published var pauseMonitoring: Bool { didSet { UserDefaults.standard.set(pauseMonitoring, forKey: Keys.pauseMonitoring) } }
    @Published var autoPaste: Bool { didSet { UserDefaults.standard.set(autoPaste, forKey: Keys.autoPaste) } }
    @Published var watchDesktopScreenshots: Bool { didSet { UserDefaults.standard.set(watchDesktopScreenshots, forKey: Keys.watchDesktopScreenshots) } }
    @Published var persistTempClips: Bool { didSet { UserDefaults.standard.set(persistTempClips, forKey: Keys.persistTempClips) } }
    @Published var globalShortcut: KeyCombo {
        didSet {
            guard let encoded = try? JSONEncoder().encode(globalShortcut) else { return }
            UserDefaults.standard.set(encoded, forKey: Keys.globalShortcut)
        }
    }

    // Optional extras, unassigned by default. Shipping defaults for these
    // would mean claiming three more system-wide combinations uninvited, which
    // is a good way to collide with whatever the user already has bound.
    @Published var pasteLastShortcut: KeyCombo? {
        didSet { Self.store(pasteLastShortcut, forKey: Keys.pasteLastShortcut) }
    }
    @Published var openPermanentShortcut: KeyCombo? {
        didSet { Self.store(openPermanentShortcut, forKey: Keys.openPermanentShortcut) }
    }
    @Published var togglePauseShortcut: KeyCombo? {
        didSet { Self.store(togglePauseShortcut, forKey: Keys.togglePauseShortcut) }
    }

    /// Reassigned in-panel shortcuts, keyed by `PanelAction.rawValue`. Only
    /// overrides are stored, so defaults keep working if an action is added.
    @Published var panelShortcuts: [String: LocalShortcut] {
        didSet {
            guard let encoded = try? JSONEncoder().encode(panelShortcuts) else { return }
            UserDefaults.standard.set(encoded, forKey: Keys.panelShortcuts)
        }
    }

    func shortcut(for action: PanelAction) -> LocalShortcut {
        panelShortcuts[action.rawValue] ?? action.defaultShortcut
    }

    /// Assigns a shortcut, refusing a key already used by another action.
    ///
    /// SwiftUI silently picks one winner when two buttons share a shortcut, so
    /// without this check a duplicate would look accepted while quietly
    /// breaking whichever action lost.
    func setShortcut(_ shortcut: LocalShortcut, for action: PanelAction) -> String? {
        if let clash = PanelAction.allCases.first(where: { other in
            other != action && self.shortcut(for: other) == shortcut
        }) {
            return "Already used by “\(clash.title)”"
        }
        panelShortcuts[action.rawValue] = shortcut
        return nil
    }

    func resetPanelShortcuts() {
        panelShortcuts = [:]
    }

    private static func store(_ combo: KeyCombo?, forKey key: String) {
        let defaults = UserDefaults.standard
        guard let combo, let encoded = try? JSONEncoder().encode(combo) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(encoded, forKey: key)
    }

    private static func loadCombo(forKey key: String) -> KeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    var maxImageBytes: Int { maxImageMB * 1024 * 1024 }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            Keys.tempCapacity: 30,
            Keys.expirySeconds: 86400.0,
            Keys.maxImageMB: 50,
            Keys.captureText: true,
            Keys.captureImages: true,
            Keys.captureFiles: true,
            Keys.captureRichText: true,
            Keys.pauseMonitoring: false,
            Keys.autoPaste: false,
            Keys.watchDesktopScreenshots: true,
            Keys.persistTempClips: false
        ])
        self.tempCapacity = d.integer(forKey: Keys.tempCapacity)
        self.expirySeconds = d.double(forKey: Keys.expirySeconds)
        self.maxImageMB = d.integer(forKey: Keys.maxImageMB)
        self.captureText = d.bool(forKey: Keys.captureText)
        self.captureImages = d.bool(forKey: Keys.captureImages)
        self.captureFiles = d.bool(forKey: Keys.captureFiles)
        self.captureRichText = d.bool(forKey: Keys.captureRichText)
        self.pauseMonitoring = d.bool(forKey: Keys.pauseMonitoring)
        self.autoPaste = d.bool(forKey: Keys.autoPaste)
        self.watchDesktopScreenshots = d.bool(forKey: Keys.watchDesktopScreenshots)
        self.persistTempClips = d.bool(forKey: Keys.persistTempClips)
        if let stored = d.data(forKey: Keys.globalShortcut),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: stored) {
            self.globalShortcut = combo
        } else {
            self.globalShortcut = .defaultCombo
        }
        self.pasteLastShortcut = Self.loadCombo(forKey: Keys.pasteLastShortcut)
        self.openPermanentShortcut = Self.loadCombo(forKey: Keys.openPermanentShortcut)
        self.togglePauseShortcut = Self.loadCombo(forKey: Keys.togglePauseShortcut)
        if let data = d.data(forKey: Keys.panelShortcuts),
           let decoded = try? JSONDecoder().decode([String: LocalShortcut].self, from: data) {
            self.panelShortcuts = decoded
        } else {
            self.panelShortcuts = [:]
        }
    }

    func resetToDefaults() {
        tempCapacity = 30
        expirySeconds = 86400
        maxImageMB = 50
        captureText = true
        captureImages = true
        captureFiles = true
        captureRichText = true
        pauseMonitoring = false
        autoPaste = false
        watchDesktopScreenshots = true
        persistTempClips = false
        globalShortcut = .defaultCombo
        pasteLastShortcut = nil
        openPermanentShortcut = nil
        togglePauseShortcut = nil
        panelShortcuts = [:]
    }
}

/// Lets a global hotkey decide which tab the panel opens on.
///
/// `activeTab` is view state, so an outside caller can't set it directly. The
/// request is parked here and consumed when the panel appears.
final class PanelRouter: ObservableObject {
    static let shared = PanelRouter()
    @Published var requestedTab: String?

    private init() {}
}

// --- AUTO-PASTE: tracks the last non-ClipSave app and simulates ⌘V ---
final class AutoPaste {
    static let shared = AutoPaste()
    private(set) var lastAppBundleID: String?
    private var observer: NSObjectProtocol?

    private init() {}

    func startTrackingFrontmostApp() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self?.lastAppBundleID = app.bundleIdentifier
            }
        }
        // Also seed with current frontmost if not us.
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastAppBundleID = app.bundleIdentifier
        }
    }

    /// Returns true if the system grants the Accessibility permission needed to post key events.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Show the macOS prompt asking the user to grant Accessibility.
    static func promptForAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Reactivate the last non-ClipSave app and simulate ⌘V there.
    func pasteIntoPreviousApp() {
        guard let id = lastAppBundleID,
              let app = NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == id }) else { return }
        app.activate(options: [])
        // Tiny delay so the activation lands before we post the keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.simulateCommandV()
        }
    }

    private static func simulateCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

// --- DATA MODEL ---
nonisolated enum ClipContent: Codable, Equatable, Sendable {
    case text(String)
    case richText(Data, String) // RTF data + plain-text preview
    case image(Data)            // PNG data
    case file(URL)

    var displayText: String {
        switch self {
        case .text(let s): return s
        case .richText(_, let preview): return preview
        case .image: return "Image"
        case .file(let url): return url.lastPathComponent
        }
    }

    var searchableText: String {
        switch self {
        case .text(let s): return s
        case .richText(_, let preview): return preview
        case .image: return ""
        case .file(let url): return url.lastPathComponent
        }
    }

    /// The textual payload, or `nil` for content that isn't text at all.
    var plainText: String? {
        switch self {
        case .text(let s): return s
        case .richText(_, let preview): return preview
        case .image, .file: return nil
        }
    }

    /// The clip parsed as a link — but only when the link is *all* it is, so
    /// prose that happens to mention a URL stays a text clip.
    var detectedURL: URL? {
        guard let raw = plainText else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "ftp", "file"].contains(scheme)
        else { return nil }
        return url
    }

    /// The clip parsed as a colour literal, on the same whole-string basis.
    var detectedColor: DetectedColor? {
        guard let raw = plainText else { return nil }
        return DetectedColor.parse(raw)
    }

    /// Full-content fingerprint.
    ///
    /// Expensive for large images, so it is computed exactly once per clip and
    /// carried in `Clip.contentHash` — never called from view code.
    func computeHash() -> String {
        switch self {
        case .text(let s):
            return "t:" + ContentHash.hex(of: s)
        case .richText(_, let preview):
            return "r:" + ContentHash.hex(of: preview)
        case .image(let data):
            // Hashes every byte. v3.4 keyed on byte count plus the first 64
            // bytes, which are near-identical across PNGs of matching
            // dimensions, so two different screenshots of the same size could
            // collide and the second would be silently dropped as a duplicate.
            return "i:" + ContentHash.hex(of: data)
        case .file(let url):
            return "f:" + ContentHash.hex(of: url.path)
        }
    }

    var kind: String {
        switch self {
        case .text: return "text"
        case .richText: return "richText"
        case .image: return "image"
        case .file: return "file"
        }
    }
}

struct Clip: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let content: ClipContent
    /// When the clip was last copied. Re-copying an existing clip promotes it
    /// back to the top and refreshes this, so auto-expiry measures idle time
    /// rather than age.
    var timestamp: Date

    /// Full-content fingerprint, computed once here so that neither
    /// de-duplication nor row rendering ever hashes a multi-megabyte image.
    let contentHash: String

    /// Derived presentation facts, cached for the same reason: the filter chip
    /// counts and every visible row would otherwise re-parse each clip's text
    /// on every redraw.
    let detectedURL: URL?
    let detectedColor: DetectedColor?

    var text: String { content.displayText }

    init(content: ClipContent, timestamp: Date = Date()) {
        self.content = content
        self.timestamp = timestamp
        self.contentHash = content.computeHash()
        self.detectedURL = content.detectedURL
        self.detectedColor = content.detectedColor
    }

    /// Rehydrates a clip whose fingerprint was already computed in a previous
    /// launch, used when loading persisted history.
    init(id: UUID, content: ClipContent, timestamp: Date, contentHash: String) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.contentHash = contentHash
        self.detectedURL = content.detectedURL
        self.detectedColor = content.detectedColor
    }

    // Custom Codable for backward-compat with legacy `{ id, text, timestamp }` JSON.
    private enum CodingKeys: String, CodingKey {
        case id, content, timestamp, text, contentHash
    }

    // Explicitly nonisolated: hand-written conformance members don't pick this
    // up from the type declaration, which would leave `Codable` main-actor
    // isolated and unusable from background work such as the history store.
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.timestamp = (try? c.decode(Date.self, forKey: .timestamp)) ?? Date()
        if let content = try? c.decode(ClipContent.self, forKey: .content) {
            self.content = content
        } else if let legacy = try? c.decode(String.self, forKey: .text) {
            self.content = .text(legacy)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .content, in: c,
                debugDescription: "Clip has no content or legacy text"
            )
        }
        // Files written before v3.5 have no stored hash; recompute so existing
        // permanent clips still de-duplicate against newly copied ones.
        self.contentHash = (try? c.decode(String.self, forKey: .contentHash))
            ?? self.content.computeHash()
        self.detectedURL = self.content.detectedURL
        self.detectedColor = self.content.detectedColor
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(contentHash, forKey: .contentHash)
    }
}

// --- LOGIC ---
class ClipboardManager: ObservableObject {
    /// Reachable without going through the app delegate, for the same reason
    /// as `HotKeyCenter.shared`: Settings needs it, and `AppDelegate.shared`
    /// proved unreliable under `@NSApplicationDelegateAdaptor`.
    static let shared = ClipboardManager()

    /// Persisting on `didSet` rather than at each mutation site means clips
    /// added from the text field, promoted, expired, or capacity-trimmed are
    /// all covered without every caller having to remember.
    @Published var tempClips: [Clip] = [] {
        didSet { persistTemporaryIfNeeded() }
    }
    @Published var permClips: [Clip] = []
    @Published var lastEvent: String = "idle"
    /// Set while history cannot be written to disk (most often a full disk).
    /// Clips keep working from memory; this just tells the user.
    @Published var diskWarning: String?

    private var saveFailures: [String: Error] = [:]
    private var saveRetry: Task<Void, Never>?

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let permFile = "perm-clips-native.json"
    private var pollTimer: Timer?
    /// Suppresses persistence while the initial load is populating the array.
    private var isRestoring = false

    private lazy var desktopWatcher = DesktopScreenshotWatcher { [weak self] url in
        self?.captureScreenshotFromDisk(url)
    }


    init() {
        TempHistoryStore.shared.onSaveResult = { [weak self] error in
            self?.noteSave("temp", error: error)
        }
        loadPermanent()
        restoreTemporaryIfNeeded()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
        // Capture whatever is already on the clipboard at launch
        // (e.g. a screenshot taken before ClipSave was opened).
        self.lastChangeCount -= 1
        checkClipboard()

        updateDesktopWatcher()
    }

    deinit {
        pollTimer?.invalidate()
    }

    // MARK: - Temporary history persistence

    private func restoreTemporaryIfNeeded() {
        guard AppSettings.shared.persistTempClips else { return }
        let restored = TempHistoryStore.shared.load(maxImageBytes: AppSettings.shared.maxImageBytes)
        guard !restored.isEmpty else { return }
        isRestoring = true
        tempClips = restored
        isRestoring = false
        lastEvent = "restored \(restored.count) clip\(restored.count == 1 ? "" : "s")"
    }

    private func persistTemporaryIfNeeded() {
        guard !isRestoring, AppSettings.shared.persistTempClips else { return }
        TempHistoryStore.shared.scheduleSave(tempClips)
    }

    /// Called when the persistence toggle changes, to write the current history
    /// immediately or erase what's already on disk.
    func persistenceSettingChanged() {
        if AppSettings.shared.persistTempClips {
            TempHistoryStore.shared.scheduleSave(tempClips)
        } else {
            TempHistoryStore.shared.clear()
        }
    }

    /// Flushes pending history to disk. The debounce would otherwise lose the
    /// last few seconds of clips on quit.
    func flushTemporary() {
        guard AppSettings.shared.persistTempClips else { return }
        TempHistoryStore.shared.saveNow(tempClips)
    }

    // MARK: - Insertion

    /// Adds a clip to the top, promoting an existing duplicate rather than
    /// storing it twice.
    ///
    /// v3.4 only compared against `tempClips.first`, so copying A, then B, then
    /// A again left two copies of A in the list.
    @discardableResult
    func insertTemporary(_ clip: Clip) -> Bool {
        if let index = tempClips.firstIndex(where: { $0.contentHash == clip.contentHash }) {
            // Already at the top: nothing to do beyond refreshing its age.
            var promoted = tempClips[index]
            promoted.timestamp = Date()
            tempClips.remove(at: index)
            tempClips.insert(promoted, at: 0)
            enforceCapacity()
            return false
        }
        tempClips.insert(clip, at: 0)
        enforceCapacity()
        return true
    }

    /// Brings the Desktop watcher in line with the current settings. Called at
    /// launch and whenever a setting it depends on changes. Starting is
    /// idempotent, so repeat calls never re-ask for Desktop permission.
    func updateDesktopWatcher() {
        let settings = AppSettings.shared
        let shouldWatch = settings.watchDesktopScreenshots
            && settings.captureImages
            && !settings.pauseMonitoring

        if shouldWatch {
            desktopWatcher.start()
            if let failure = desktopWatcher.failureMessages.first {
                lastEvent = "⚠️ \(failure)"
            }
        } else {
            desktopWatcher.stop()
        }
    }

    /// Reads a screenshot that has just appeared on disk.
    ///
    /// The kernel reports the file as soon as it is created, which for a
    /// multi-megabyte screenshot is well before it has finished being written.
    /// Rather than guess one delay, wait until the size stops changing — a
    /// fixed 0.2 s was enough for a small capture but truncated large ones.
    private func captureScreenshotFromDisk(_ url: URL, attempt: Int = 0, lastSize: Int = -1) {
        let maxAttempts = 15 // ~3s at 200 ms, enough for a very large capture

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? Int else { return } // moved or deleted

            // Empty or still growing — check again shortly.
            if size == 0 || size != lastSize {
                guard attempt < maxAttempts else { return }
                self.captureScreenshotFromDisk(url, attempt: attempt + 1, lastSize: size)
                return
            }

            guard size <= self.maxImageBytes else {
                self.lastEvent = "⚠️ screenshot too big (\(self.formatBytes(size)))"
                return
            }
            guard let data = try? Data(contentsOf: url) else { return }

            var pngData = data
            if url.pathExtension.lowercased() != "png" {
                guard let img = NSImage(data: data),
                      let tiff = img.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { return }
                pngData = png
            }

            let clip = Clip(content: .image(pngData))
            guard self.insertTemporary(clip) else { return }
            self.lastEvent = "✅ screenshot: \(url.lastPathComponent)"
        }
    }

    private var maxImageBytes: Int { AppSettings.shared.maxImageBytes }

    private func expireOldTempClips() {
        let settings = AppSettings.shared
        guard settings.expirySeconds != AppSettings.neverExpire else { return }
        let cutoff = Date().addingTimeInterval(-settings.expirySeconds)
        let before = tempClips.count
        tempClips.removeAll { $0.timestamp < cutoff }
        let removed = before - tempClips.count
        if removed > 0 {
            lastEvent = "⏱ auto-expired \(removed) clip\(removed == 1 ? "" : "s")"
        }
    }

    private func enforceCapacity() {
        let cap = AppSettings.shared.tempCapacity
        while tempClips.count > cap { tempClips.removeLast() }
    }

    private func checkClipboard() {
        expireOldTempClips()
        enforceCapacity()

        if AppSettings.shared.pauseMonitoring {
            return
        }

        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let content = readContent(from: pb) else { return }
        insertTemporary(Clip(content: content))
    }

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "heic", "heif", "webp"
    ]

    private func formatBytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private func readContent(from pb: NSPasteboard) -> ClipContent? {
        let settings = AppSettings.shared
        let availableTypes = (pb.types ?? []).map { $0.rawValue }

        // 1. File URLs
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], let first = urls.first {
            let ext = first.pathExtension.lowercased()
            if Self.imageExtensions.contains(ext), settings.captureImages {
                do {
                    let data = try Data(contentsOf: first)
                    if data.count > maxImageBytes {
                        lastEvent = "⚠️ image too big (\(formatBytes(data.count)))"
                        return nil
                    }
                    if ext == "png" {
                        lastEvent = "✅ image from file (\(formatBytes(data.count)))"
                        return .image(data)
                    }
                    if let img = NSImage(data: data),
                       let tiff = img.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        lastEvent = "✅ image from \(ext)→png (\(formatBytes(png.count)))"
                        return .image(png)
                    }
                    lastEvent = "⚠️ can't decode \(ext) image, stored as file"
                } catch {
                    lastEvent = "⚠️ file read denied (sandbox?): \(error.localizedDescription)"
                }
            }
            if settings.captureFiles {
                lastEvent = "✅ file: \(first.lastPathComponent)"
                return .file(first)
            }
        }

        // 2. Raw image data on pasteboard (Ctrl+⌘⇧4, copy from Safari, etc.)
        if settings.captureImages {
            if let png = pb.data(forType: .png) {
                if png.count > maxImageBytes {
                    lastEvent = "⚠️ image too big (\(formatBytes(png.count)))"
                    return nil
                }
                lastEvent = "✅ image (PNG \(formatBytes(png.count)))"
                return .image(png)
            }
            if let tiff = pb.data(forType: .tiff),
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                if png.count > maxImageBytes {
                    lastEvent = "⚠️ image too big (\(formatBytes(png.count)))"
                    return nil
                }
                lastEvent = "✅ image (TIFF→PNG \(formatBytes(png.count)))"
                return .image(png)
            }
        }

        // 3. Rich text
        if settings.captureRichText,
           let rtf = pb.data(forType: .rtf),
           let attr = try? NSAttributedString(
                data: rtf,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ),
           !attr.string.trimmingCharacters(in: .whitespaces).isEmpty {
            lastEvent = "✅ richText (\(attr.string.count) chars)"
            return .richText(rtf, attr.string)
        }

        // 4. Plain text
        if settings.captureText,
           let str = pb.string(forType: .string),
           !str.trimmingCharacters(in: .whitespaces).isEmpty {
            lastEvent = "✅ text (\(str.count) chars)"
            return .text(str)
        }

        let preview = availableTypes.prefix(3).joined(separator: ", ")
        lastEvent = "⚠️ no usable content [\(preview)]"
        return nil
    }

    func forceCheck() {
        lastChangeCount -= 1
        checkClipboard()
    }

    func clearTemporary() {
        tempClips.removeAll()
        lastEvent = "cleared"
    }

    func clearPermanent() {
        permClips.removeAll()
        savePermanent()
        lastEvent = "cleared permanent"
    }

    @discardableResult
    func pinClip(_ clip: Clip) -> Bool {
        guard !permClips.contains(where: { $0.contentHash == clip.contentHash }) else { return false }
        permClips.insert(clip, at: 0)
        savePermanent()
        return true
    }

    func deleteClip(_ clip: Clip, fromTab: String) {
        if fromTab == "temp" {
            tempClips.removeAll(where: { $0.id == clip.id })
            if tempClips.isEmpty { lastEvent = "idle" }
        } else {
            permClips.removeAll(where: { $0.id == clip.id })
            savePermanent()
        }
    }

    /// Puts plain text on the pasteboard without recording a new clip.
    ///
    /// Used by the transform and colour-conversion actions: they are meant to
    /// be non-destructive, so the history keeps showing what was originally
    /// copied rather than gaining an entry for every reformatting.
    func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    func copyBack(_ clip: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .richText(let data, let plain):
            pb.setData(data, forType: .rtf)
            pb.setString(plain, forType: .string)
        case .image(let data):
            pb.setData(data, forType: .png)
        case .file(let url):
            pb.writeObjects([url as NSURL])
        }
        self.lastChangeCount = pb.changeCount
    }
    
    private func savePermanent() {
        guard let encoded = try? JSONEncoder().encode(permClips) else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(permFile)
        do {
            // Atomic: a full disk must not leave a half-written file in place
            // of the pinned clips that were there before.
            try encoded.write(to: url, options: .atomic)
            noteSave("perm", error: nil)
        } catch {
            noteSave("perm", error: error)
        }
    }

    // MARK: - Save failures

    nonisolated static func isOutOfSpace(_ error: Error) -> Bool {
        if (error as? CocoaError)?.code == .fileWriteOutOfSpace { return true }
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(ENOSPC) {
            return true
        }
        return false
    }

    private func noteSave(_ source: String, error: Error?) {
        if let error {
            saveFailures[source] = error
        } else {
            saveFailures[source] = nil
        }

        if let first = saveFailures.values.first {
            diskWarning = Self.isOutOfSpace(first)
                ? "Disk almost full — history not saved"
                : "Couldn't save clips to disk"
            scheduleSaveRetry()
        } else {
            diskWarning = nil
            saveRetry?.cancel()
            saveRetry = nil
        }
    }

    /// Tries again on its own, so clips are written as soon as space is freed
    /// without the user having to do anything.
    private func scheduleSaveRetry() {
        guard saveRetry == nil else { return }
        saveRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            self.saveRetry = nil
            if self.saveFailures["perm"] != nil { self.savePermanent() }
            if self.saveFailures["temp"] != nil, AppSettings.shared.persistTempClips {
                TempHistoryStore.shared.scheduleSave(self.tempClips)
            }
        }
    }
    
    private func loadPermanent() {
        let standardURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(permFile)

        if let data = try? Data(contentsOf: standardURL),
           let decoded = try? JSONDecoder().decode([Clip].self, from: data),
           !decoded.isEmpty {
            permClips = decoded
            return
        }

        // Fallback: data was saved here when the App Sandbox was enabled.
        // After sandbox removal, the documentDirectory points to ~/Documents,
        // so we look in the old container path and migrate.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sandboxedURL = home
            .appendingPathComponent("Library/Containers/som.ClipSave/Data/Documents")
            .appendingPathComponent(permFile)

        if let data = try? Data(contentsOf: sandboxedURL),
           let decoded = try? JSONDecoder().decode([Clip].self, from: data),
           !decoded.isEmpty {
            permClips = decoded
            // Migrate to the new location so we don't have to do this again.
            savePermanent()
            lastEvent = "✅ migrated \(decoded.count) permanent clip\(decoded.count == 1 ? "" : "s")"
        }
    }

}

// --- UI ---
struct ContentView: View {
    @ObservedObject var manager: ClipboardManager
    @State private var activeTab = "temp"
    @State private var inputText = ""
    @State private var copiedClipID: UUID?
    @State private var searchText = ""
    @State private var appeared = false
    @State private var selectedIndex: Int = 0
    @State private var toastMessage: String? = nil
    @State private var activeFilter: ClipFilter = .all
    @State private var quickLookClip: Clip?
    @FocusState private var searchFocused: Bool
    @FocusState private var addFieldFocused: Bool
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var router = PanelRouter.shared
    @Environment(\.openSettings) private var openSettings

    /// True while a text field holds focus, in which case list keys must not
    /// fire. v3.4 left ⌫ live unconditionally, so backspacing a typo in the
    /// search field deleted the selected clip.
    private var isTypingInField: Bool { searchFocused || addFieldFocused }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.25)) {
                toastMessage = nil
            }
        }
    }

    private var sourceClips: [Clip] {
        activeTab == "temp" ? manager.tempClips : manager.permClips
    }

    private func matchesSearch(_ clip: Clip) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return clip.content.searchableText.localizedCaseInsensitiveContains(query)
    }

    private var visibleClips: [Clip] {
        sourceClips.filter { matchesSearch($0) && activeFilter.matches($0) }
    }

    /// Chip counts are computed after the tab and search text are applied, so
    /// each number describes exactly what selecting that chip would show.
    private var filterCounts: [ClipFilter: Int] {
        let searched = sourceClips.filter(matchesSearch)
        var counts: [ClipFilter: Int] = [:]
        for filter in ClipFilter.allCases {
            counts[filter] = filter == .all
                ? searched.count
                : searched.filter { filter.matches($0) }.count
        }
        return counts
    }

    /// With a filter active the footer reports the narrowing, so a short list
    /// is never mistaken for a short history.
    private var footerStatus: String {
        guard activeFilter != .all else { return manager.lastEvent }
        return "\(activeFilter.title) · \(visibleClips.count) of \(sourceClips.count)"
    }

    private var emptyStateKind: EmptyStateView.Kind {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { return .noSearchMatches(query: query) }
        if activeFilter != .all { return .noFilterMatches(activeFilter) }
        return activeTab == "temp" ? .noTemporaryClips : .noPermanentClips
    }

    private func moveSelection(by delta: Int) {
        guard !visibleClips.isEmpty else { return }
        selectedIndex = max(0, min(visibleClips.count - 1, selectedIndex + delta))
    }

    private func copyClip(at index: Int, dismissAfter: Bool = true) {
        guard index >= 0, index < visibleClips.count else { return }
        let clip = visibleClips[index]
        manager.copyBack(clip)
        copiedClipID = clip.id
        if dismissAfter {
            performDismissAndMaybePaste()
        }
    }

    private func performDismissAndMaybePaste() {
        let shouldPaste = AppSettings.shared.autoPaste && AutoPaste.hasAccessibilityPermission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.keyWindow?.orderOut(nil)
            if shouldPaste {
                AutoPaste.shared.pasteIntoPreviousApp()
            }
        }
    }

    private func deleteSelectedClip() {
        guard selectedIndex >= 0, selectedIndex < visibleClips.count else { return }
        let clip = visibleClips[selectedIndex]
        manager.deleteClip(clip, fromTab: activeTab)
        if selectedIndex >= visibleClips.count && selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    private func dismissPanel() {
        NSApp.keyWindow?.orderOut(nil)
    }

    /// Esc closes Quick Look first, then the panel — a single handler so the
    /// two never race for `.cancelAction`.
    private func handleCancel() {
        if quickLookClip != nil {
            quickLookClip = nil
        } else {
            dismissPanel()
        }
    }

    private func toggleQuickLook() {
        if quickLookClip != nil {
            quickLookClip = nil
            return
        }
        guard selectedIndex >= 0, selectedIndex < visibleClips.count else { return }
        let clip = visibleClips[selectedIndex]
        // Only image clips have anything worth previewing.
        guard case .image = clip.content else { return }
        quickLookClip = clip
    }

    /// Copies the transformed text without touching the stored clip.
    private func applyTransform(_ transform: TextTransform, to clip: Clip) {
        guard let output = transform.output(for: clip.content) else { return }
        manager.copyText(output)
        copiedClipID = clip.id
        showToast("\(transform.title) copied")
    }

    private func applyTransformToSelection(_ transform: TextTransform) {
        guard selectedIndex >= 0, selectedIndex < visibleClips.count else { return }
        applyTransform(transform, to: visibleClips[selectedIndex])
    }

    private func copyColorValue(_ value: String, label: String) {
        manager.copyText(value)
        showToast("\(label) copied")
    }

    @ViewBuilder
    private func contextMenu(for clip: Clip) -> some View {
        Button("Copy") {
            manager.copyBack(clip)
            copiedClipID = clip.id
        }
        if activeTab == "temp" {
            Button("Pin to Permanent") {
                if manager.pinClip(clip) { showToast("📌 Pinned") }
            }
        }
        if case .image = clip.content {
            Button("Quick Look") { quickLookClip = clip }
        }

        // Only transforms that would actually change the text show up, so the
        // menu stays short for ordinary clips.
        let transforms = TextTransform.allCases.filter { $0.output(for: clip.content) != nil }
        if !transforms.isEmpty {
            Section("Transform & Copy") {
                ForEach(transforms) { transform in
                    Button(transform.title) { applyTransform(transform, to: clip) }
                }
            }
        }

        if let color = clip.detectedColor {
            Section("Colour") {
                Button("Copy as HEX") { copyColorValue(color.hexString, label: "HEX") }
                Button("Copy as RGB") { copyColorValue(color.rgbString, label: "RGB") }
                Button("Copy as HSL") { copyColorValue(color.hslString, label: "HSL") }
            }
        }

        Divider()
        Button("Delete", role: .destructive) {
            manager.deleteClip(clip, fromTab: activeTab)
        }
    }

    private func addTypedClip() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let new = Clip(content: .text(trimmed))
        if activeTab == "temp" {
            manager.insertTemporary(new)
        } else {
            manager.pinClip(new)
        }
        inputText = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabBtn(title: "⏱ Temporary", id: "temp", current: $activeTab, count: manager.tempClips.count)
                TabBtn(title: "📌 Permanent", id: "perm", current: $activeTab, count: manager.permClips.count)
                Menu {
                    Button("Refresh from Clipboard") { manager.forceCheck() }
                    Button("Settings...") {
                        openSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    Button("Check for Updates...") {
                        NSApp.keyWindow?.orderOut(nil)
                        let delegate = AppDelegate.shared
                        delegate?.enterForeground(reason: "sparkle")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            delegate?.updaterController.checkForUpdates(nil)
                        }
                    }
                    Divider()
                    Button("Clear Temporary") { manager.clearTemporary() }
                        .disabled(manager.tempClips.isEmpty)
                    Button("Clear Permanent", role: .destructive) {
                        manager.clearPermanent()
                    }
                    .disabled(manager.permClips.isEmpty)
                    Divider()
                    Button("Quit ClipSave") {
                        // Tells the keep-alive agent this stop is deliberate.
                        KeepAlive.markUserQuit()
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 36)
                .help("Menu")

                Button(action: dismissPanel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .background(Color.primary.opacity(0.06))
            .onChange(of: activeTab) { _, _ in
                searchText = ""
                selectedIndex = 0
                quickLookClip = nil
            }
            .onChange(of: searchText) { _, _ in
                selectedIndex = 0
            }
            .onChange(of: activeFilter) { _, _ in
                selectedIndex = 0
                quickLookClip = nil
            }
            .onChange(of: manager.tempClips.count) { _, _ in
                if selectedIndex >= visibleClips.count {
                    selectedIndex = max(0, visibleClips.count - 1)
                }
            }
            .onChange(of: manager.permClips.count) { _, _ in
                if selectedIndex >= visibleClips.count {
                    selectedIndex = max(0, visibleClips.count - 1)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Search clips...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.top, 10)

            FilterChipsView(selection: $activeFilter, counts: filterCounts)
                .padding(.top, 8)

            HStack {
                TextField(activeTab == "temp" ? "Add to temp..." : "Save permanent...", text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($addFieldFocused)
                    .padding(8)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(6)
                    .onSubmit(addTypedClip)

                Button(activeTab == "temp" ? "+Temp" : "Save", action: addTypedClip)
                    .tint(activeTab == "temp" ? .blue : .orange)
                    .buttonStyle(.borderedProminent)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 6) {
                        let list = visibleClips
                        if list.isEmpty {
                            EmptyStateView(
                                kind: emptyStateKind,
                                shortcutDisplay: settings.globalShortcut.display,
                                onReset: {
                                    searchText = ""
                                    activeFilter = .all
                                }
                            )
                        } else {
                            ForEach(Array(list.enumerated()), id: \.element.id) { index, clip in
                                ClipRow(
                                    clip: clip,
                                    tab: activeTab,
                                    manager: manager,
                                    isCopied: copiedClipID == clip.id,
                                    isSelected: index == selectedIndex,
                                    shortcutNumber: index < 9 ? index + 1 : nil,
                                    onCopy: {
                                        manager.copyBack(clip)
                                        copiedClipID = clip.id
                                        if AppSettings.shared.autoPaste {
                                            performDismissAndMaybePaste()
                                        } else {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                                if copiedClipID == clip.id {
                                                    copiedClipID = nil
                                                }
                                            }
                                        }
                                    },
                                    onPin: {
                                        if manager.pinClip(clip) {
                                            showToast("📌 Pinned")
                                        } else {
                                            showToast("Already pinned")
                                        }
                                    }
                                )
                                .id(index)
                                .contextMenu { contextMenu(for: clip) }
                            }
                        }
                    }
                    .padding(10)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            
            HStack(spacing: 6) {
                Text("V\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("·")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                if let warning = manager.diskWarning {
                    Text("⚠️ \(warning)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help("ClipSave keeps working from memory and will save again as soon as there is space.")
                } else {
                    Text(footerStatus)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button(action: { manager.forceCheck() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh from clipboard")
            }
            .padding(8)
        }
        .frame(width: 320, height: 480)
        .background(VisualEffect().ignoresSafeArea())
        .overlay {
            if let clip = quickLookClip, case .image(let data) = clip.content {
                QuickLookOverlay(
                    data: data,
                    pixelSize: ThumbnailCache.shared.entry(for: data, key: clip.contentHash)?.pixelSize,
                    onCopy: {
                        manager.copyBack(clip)
                        copiedClipID = clip.id
                        quickLookClip = nil
                    },
                    onDismiss: { quickLookClip = nil }
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: quickLookClip?.id)
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                Text(msg)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.78)))
                    .foregroundColor(.white)
                    .padding(.bottom, 38)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
        .onAppear {
            appeared = false
            copiedClipID = nil
            toastMessage = nil
            // A hotkey may have asked for a specific tab before we appeared.
            if let requested = router.requestedTab {
                activeTab = requested
                searchText = ""
                selectedIndex = 0
                router.requestedTab = nil
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                appeared = true
            }
        }
        .background(keyboardShortcuts)
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Group {
            Group {
                shortcutButton(.moveUp) { moveSelection(by: -1) }
                shortcutButton(.moveDown) { moveSelection(by: 1) }
                shortcutButton(.copyAndClose) { copyClip(at: selectedIndex) }
                    // Return belongs to the add-field while that field has focus.
                    .disabled(addFieldFocused)
                shortcutButton(.deleteClip) { deleteSelectedClip() }
                    .disabled(isTypingInField)
                shortcutButton(.formatJSON) { applyTransformToSelection(.formatJSON) }
                ForEach(1...9, id: \.self) { num in
                    Button("") { copyClip(at: num - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(num)")), modifiers: .command)
                }
            }
            // While Quick Look is up it owns the keyboard; only Quick Look and
            // Close stay live, and both are declared outside this group.
            .disabled(quickLookClip != nil)

            shortcutButton(.focusSearch) { searchFocused = true }
            shortcutButton(.quickLook) { toggleQuickLook() }
                // A bare key like Space must still reach the text fields as an
                // ordinary character.
                .disabled(isTypingInField && settings.shortcut(for: .quickLook).modifiers.isEmpty)
            shortcutButton(.close) { handleCancel() }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// A hidden button bound to whatever key the action is currently assigned.
    private func shortcutButton(_ action: PanelAction,
                                perform: @escaping () -> Void) -> some View {
        let shortcut = settings.shortcut(for: action)
        return Button("", action: perform)
            .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers)
    }
}

struct TabBtn: View {
    let title: String; let id: String; @Binding var current: String; let count: Int
    var body: some View {
        Button(action: { current = id }) {
            VStack {
                Text(verbatim: "\(title) (\(count))").font(.system(size: 12, weight: current == id ? .bold : .regular))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(current == id ? (id == "temp" ? .blue : .orange) : .clear).frame(height: 2)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
    }
}

struct ClipRow: View {
    let clip: Clip; let tab: String; @ObservedObject var manager: ClipboardManager
    let isCopied: Bool
    let isSelected: Bool
    /// `⌘1`–`⌘9` badge, or `nil` past the ninth row.
    let shortcutNumber: Int?
    let onCopy: () -> Void
    let onPin: () -> Void
    @State private var isHovered = false
    @State private var showLargePreview = false
    @State private var hoverIntent: Task<Void, Never>?

    private var fileURL: URL? {
        if case .file(let url) = clip.content { return url }
        return nil
    }

    private var imageData: Data? {
        if case .image(let data) = clip.content { return data }
        return nil
    }

    /// Row hover drives both the action buttons and the image preview.
    ///
    /// The preview opens from anywhere in the row rather than only the
    /// thumbnail, and only after a short dwell — without the delay, dragging
    /// the cursor down the list flashes a popover over every image on the way
    /// past.
    private func hoverChanged(_ isHovering: Bool) {
        isHovered = isHovering
        hoverIntent?.cancel()
        guard isHovering, imageData != nil else {
            showLargePreview = false
            return
        }
        hoverIntent = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            showLargePreview = true
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(tab == "temp" ? Color.blue : Color.orange).frame(width: 8, height: 8)

            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
            }

            HStack(spacing: 8) {
                if let url = clip.detectedURL {
                    Button(action: { NSWorkspace.shared.open(url) }) {
                        Image(systemName: "link")
                    }
                    .help("Open Link")
                }

                if let url = fileURL {
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }) {
                        Image(systemName: "folder")
                    }
                    .help("Reveal in Finder")
                }

                if tab == "temp" {
                    Button(action: { onPin() }) {
                        Image(systemName: "pin")
                    }
                    .help("Pin")
                }

                Button(action: { manager.deleteClip(clip, fromTab: tab) }) {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .frame(width: actionWidth, alignment: .trailing)
            .opacity(isHovered ? 1 : 0)

            if let shortcutNumber {
                Text(verbatim: "⌘\(shortcutNumber)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(isSelected ? 0.22 : 0.13))
                    )
            }
        }
        .padding(8)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onTapGesture {
            onCopy()
        }
        .onHover(perform: hoverChanged)
        .popover(isPresented: $showLargePreview, arrowEdge: .trailing) {
            if let data = imageData,
               let preview = ThumbnailCache.shared.preview(for: data, key: clip.contentHash) {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 480, maxHeight: 360)
                    .padding(8)
            }
        }
    }

    /// A tinted fill plus a border ring. At 320 pt wide a flat wash — which is
    /// all v3.4 drew — reads as "disabled" more readily than "selected".
    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch clip.content {
        case .text(let s):
            if let color = clip.detectedColor {
                ColorClipPreview(value: s.trimmingCharacters(in: .whitespacesAndNewlines),
                                 detected: color)
            } else {
                Text(s).lineLimit(2).font(.system(size: 13))
            }
        case .richText(_, let plain):
            HStack(spacing: 4) {
                Image(systemName: "doc.richtext").font(.system(size: 10)).foregroundColor(.secondary)
                Text(plain).lineLimit(2).italic().font(.system(size: 13))
            }
        case .image(let data):
            ImagePreview(data: data, cacheKey: clip.contentHash)
        case .file(let url):
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).lineLimit(1).font(.system(size: 13))
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var actionWidth: CGFloat {
        var w: CGFloat = 20 // delete
        if clip.detectedURL != nil { w += 22 }
        if fileURL != nil { w += 22 }
        if tab == "temp" { w += 22 } // pin
        return w
    }
}

struct ImagePreview: View {
    let data: Data
    /// The clip's content hash, so the decoded thumbnail is shared across
    /// redraws instead of being rebuilt inside `body` the way v3.4 did.
    let cacheKey: String

    private var entry: ThumbnailEntry? {
        ThumbnailCache.shared.entry(for: data, key: cacheKey)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Hover previewing lives on the whole row, in `ClipRow`.
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot").font(.system(size: 13, weight: .medium))
                if let size = entry?.pixelSize, size.width > 0 {
                    // `verbatim` matters: interpolating an Int into a
                    // LocalizedStringKey formats it as a number, which turned
                    // 2940×1912 into "2,940×1,912".
                    Text(verbatim: "\(Int(size.width))×\(Int(size.height))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let entry {
            Image(nsImage: entry.image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipped()
                .cornerRadius(6)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.1))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
        }
    }
}

// --- SETTINGS VIEW ---
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = false
    @State private var loginItemError: String?
    @State private var keepAliveNeedsApproval = false

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            contentTab.tabItem { Label("Content", systemImage: "doc.on.clipboard") }
            advancedTab.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            shortcutsTab.tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480, height: 380)
    }

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Global shortcut")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        Text("Open ClipSave")
                            .font(.system(size: 12))
                        Spacer()
                        ShortcutRecorder(
                            combo: Binding(
                                get: { settings.globalShortcut },
                                set: { if let new = $0 { settings.globalShortcut = new } }
                            )
                        ) { candidate in
                            guard let candidate else { return nil }
                            return HotKeyCenter.shared.rebind(.openPanel, to: candidate)
                        }
                    }
                    Text("**Click the ⌘⇧V field above to change it**, then press the combination you want.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Must include ⌘, ⌃ or ⌥ — a bare key would be swallowed system-wide. If another app already owns the combination, ClipSave keeps the previous one.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional shortcuts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    optionalShortcutRow(
                        title: "Paste last clip",
                        detail: "Pastes the newest clip into whatever app you're in, without opening the panel.",
                        combo: $settings.pasteLastShortcut,
                        action: .pasteLastClip
                    )
                    optionalShortcutRow(
                        title: "Open to Permanent",
                        detail: "Opens ClipSave with the Permanent tab already selected.",
                        combo: $settings.openPermanentShortcut,
                        action: .openPermanent
                    )
                    optionalShortcutRow(
                        title: "Pause / resume capture",
                        detail: "Stops and restarts clipboard monitoring.",
                        combo: $settings.togglePauseShortcut,
                        action: .togglePause
                    )

                    Text("These are off unless you assign them, so ClipSave doesn't claim combinations you may already be using. Click ✕ to remove one.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Inside ClipSave")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Reset to defaults") { settings.resetPanelShortcuts() }
                            .controlSize(.small)
                            .disabled(settings.panelShortcuts.isEmpty)
                    }

                    ForEach(PanelAction.allCases) { action in
                        HStack(spacing: 12) {
                            Text(action.title)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PanelShortcutRecorder(
                                shortcut: Binding(
                                    get: { settings.shortcut(for: action) },
                                    set: { _ in } // committed through setShortcut
                                )
                            ) { candidate in
                                settings.setShortcut(candidate, for: action)
                            }
                        }
                    }

                    Text("These only apply while the ClipSave panel is open, so a single key such as ↑ or Space is fine. A key already used by another action is refused rather than silently taking it over.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                shortcutSection(
                    title: "Fixed shortcuts",
                    items: [
                        ("⌘,",       "Open Settings — the macOS-wide convention"),
                        ("⌘1 … ⌘9", "Instantly copy clip number 1 through 9")
                    ]
                )

                VStack(alignment: .leading, spacing: 8) {
                    shortcutSection(
                        title: "Screenshots (macOS system)",
                        items: [
                            ("⌘⇧3",      "Full-screen screenshot → captured as image clip"),
                            ("⌘⇧4",      "Rectangle screenshot → captured as image clip"),
                            ("⌃⌘⇧4",     "Rectangle to clipboard (no file) → captured instantly")
                        ]
                    )
                    HStack(spacing: 8) {
                        Text("These belong to macOS, not ClipSave — change them in System Settings → Keyboard → Keyboard Shortcuts → Screenshots.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Open…") {
                            // Deep-links to the Keyboard pane; the Screenshots
                            // group lives behind its "Keyboard Shortcuts…" button.
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(20)
        }
    }

    private func optionalShortcutRow(title: String,
                                     detail: String,
                                     combo: Binding<KeyCombo?>,
                                     action: HotKeyCenter.Action) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                ShortcutRecorder(combo: combo, allowsClearing: true) { candidate in
                    HotKeyCenter.shared.rebind(action, to: candidate)
                }
            }
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func shortcutSection(title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            VStack(spacing: 4) {
                ForEach(items, id: \.0) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.0)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                            .frame(width: 100, alignment: .leading)
                        Text(item.1)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Pause clipboard monitoring", isOn: $settings.pauseMonitoring)
                    .onChange(of: settings.pauseMonitoring) { _, _ in
                        ClipboardManager.shared.updateDesktopWatcher()
                    }
                Text("When paused, ClipSave stops capturing new clips. Existing clips remain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Auto-paste") {
                Toggle("Paste clip into the previous app", isOn: $settings.autoPaste)
                    .onChange(of: settings.autoPaste) { _, newValue in
                        if newValue && !AutoPaste.hasAccessibilityPermission {
                            AutoPaste.promptForAccessibility()
                        }
                    }
                Text("When you pick a clip, ClipSave returns to the previous app and presses ⌘V for you. Requires Accessibility permission (you'll be prompted).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if settings.autoPaste && !AutoPaste.hasAccessibilityPermission {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Grant Accessibility in System Settings → Privacy & Security to enable.")
                            .font(.caption)
                    }
                }
            }
            Section("History") {
                Toggle("Keep temporary clips after quitting", isOn: $settings.persistTempClips)
                    .onChange(of: settings.persistTempClips) { _, _ in
                        ClipboardManager.shared.persistenceSettingChanged()
                    }
                Text("Temporary clips are restored on next launch. Images are written as separate files in Application Support rather than inlined, so the history index stays small.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Open ClipSave at login and keep it running", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        loginItemError = LoginItem.setEnabled(newValue)
                        // Show what the system actually did, not what we asked
                        // for — registration can be refused pending approval.
                        let actual = LoginItem.isEnabled
                        if actual != newValue { launchAtLogin = actual }
                    }
                Text("ClipSave starts when you log in and reopens itself if macOS stops it. Choosing Quit from the menu keeps it closed until your next login.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if launchAtLogin && keepAliveNeedsApproval {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Allow ClipSave under “Allow in the Background” so it can reopen itself.")
                            .font(.caption)
                        Spacer()
                        Button("Open…") { LoginItem.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
                if let loginItemError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(loginItemError)
                            .font(.caption)
                        Spacer()
                        Button("Open…") { LoginItem.openSystemSettings() }
                            .controlSize(.small)
                    }
                }
            }
            Section("Temporary clips") {
                HStack {
                    Text("Max clips: \(settings.tempCapacity)")
                    Spacer()
                    Stepper("", value: $settings.tempCapacity, in: 10...200, step: 5)
                        .labelsHidden()
                }
                Picker("Auto-expire after", selection: $settings.expirySeconds) {
                    Text("Never").tag(AppSettings.neverExpire)
                    Text("1 hour").tag(TimeInterval(3600))
                    Text("24 hours").tag(TimeInterval(86400))
                    Text("7 days").tag(TimeInterval(604800))
                    Text("30 days").tag(TimeInterval(2592000))
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = LoginItem.isEnabled
            keepAliveNeedsApproval = KeepAlive.needsApproval
        }
    }

    private var contentTab: some View {
        Form {
            Section("What to capture") {
                Toggle("Plain text", isOn: $settings.captureText)
                Toggle("Rich text (formatting)", isOn: $settings.captureRichText)
                Toggle("Images / screenshots", isOn: $settings.captureImages)
                    .onChange(of: settings.captureImages) { _, _ in
                        ClipboardManager.shared.updateDesktopWatcher()
                    }
                Toggle("Files", isOn: $settings.captureFiles)
            }
            Section("Screenshots") {
                Toggle("Auto-capture saved screenshots", isOn: $settings.watchDesktopScreenshots)
                    .onChange(of: settings.watchDesktopScreenshots) { _, _ in
                        ClipboardManager.shared.updateDesktopWatcher()
                    }
                ForEach(DesktopScreenshotWatcher.candidateDirectories(), id: \.self) { folder in
                    HStack(spacing: 6) {
                        Text("Watching")
                            .foregroundColor(.secondary)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                        .controlSize(.small)
                    }
                    .font(.caption)
                }
                Text("Adds new ⌘⇧3 / ⌘⇧4 screenshots to Temporary automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Both your configured screenshot folder and the Desktop are watched, so captures are picked up either way. If the screenshot folder has been deleted, ClipSave re-creates it at launch — macOS won't, it just starts dropping files on the Desktop instead.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                Text("Disabled types are skipped when found on the clipboard. Existing clips of any type stay visible.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ClipSave \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                            .font(.system(size: 13, weight: .medium))
                        Text("Click below to check for a newer version.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates") {
                        let delegate = AppDelegate.shared
                        delegate?.enterForeground(reason: "sparkle")
                        delegate?.updaterController.checkForUpdates(nil)
                    }
                }
            }
            Section("Image limits") {
                HStack {
                    Text("Max image size: \(settings.maxImageMB) MB")
                    Spacer()
                    Stepper("", value: $settings.maxImageMB, in: 5...500, step: 5)
                        .labelsHidden()
                }
                Text("Images larger than this are skipped. Default: 50 MB.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section {
                Button("Reset all settings to defaults", role: .destructive) {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct VisualEffect: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        // Re-apply appearance whenever colorScheme changes so the blur
        // actually flips between light and dark.
        v.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
