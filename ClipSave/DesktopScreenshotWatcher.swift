import Foundation

/// Watches for screenshot files appearing on disk.
///
/// Two design decisions worth knowing about:
///
/// **Event-driven, not polled.** Reading a TCC-protected folder triggers a
/// consent check *per call*, so a 1 Hz directory scan asks the system for
/// permission once a second — and every tick that lands while the consent
/// dialog is already up queues another dialog behind it. That is what made
/// ClipSave up to v3.5 stack up identical prompts even after access was
/// granted. Each folder here is opened exactly once; afterwards the kernel
/// reports changes.
///
/// **More than one folder.** macOS has a configurable screenshot location, but
/// it does not always honour a change made outside the Screenshot UI — the
/// preference can read `~/Screenshots` while `screencapture` keeps writing to
/// the Desktop. Watching every plausible folder means screenshots are captured
/// regardless of which one wins.
@MainActor
final class DesktopScreenshotWatcher {

    /// Plain storage, deliberately outside the main actor so `deinit` — which
    /// is nonisolated — can still cancel the dispatch sources it holds.
    /// Every mutation happens on the main actor via the enclosing class.
    private nonisolated final class Watch {
        let directory: URL
        nonisolated(unsafe) var source: DispatchSourceFileSystemObject?
        nonisolated(unsafe) var knownFilenames: Set<String> = []

        init(directory: URL) {
            self.directory = directory
        }
    }

    private var watches: [Watch] = []

    /// One attempt per enable. Without this, a folder that fails to open would
    /// be retried on every `start()` — the other way an app re-prompts forever.
    private var didAttempt = false

    /// Folders we couldn't open. Latched so a refused folder is never retried
    /// within a session, no matter how many change events arrive.
    private var failedPaths: Set<String> = []

    private(set) var failureMessages: [String] = []

    private let onNewScreenshot: (URL) -> Void

    var isWatching: Bool { !watches.isEmpty }

    /// Folders currently being watched successfully.
    var activeDirectories: [URL] { watches.map(\.directory) }

    init(onNewScreenshot: @escaping (URL) -> Void) {
        self.onNewScreenshot = onNewScreenshot
    }

    deinit {
        watches.forEach { $0.source?.cancel() }
    }

    // MARK: - Locations

    /// The path macOS is configured to save screenshots to, whether or not it
    /// currently exists. The stored value may use a tilde.
    static func configuredScreenshotPath() -> URL? {
        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"),
              !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath,
                   isDirectory: true)
    }

    /// The configured folder, only if it exists and really is a directory.
    static func configuredScreenshotDirectory() -> URL? {
        guard let url = configuredScreenshotPath() else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }

    /// Re-creates the configured screenshot folder when it has gone missing.
    ///
    /// macOS does not restore a deleted screenshot destination — it silently
    /// reverts to dropping files on the Desktop — so deleting the folder once
    /// would otherwise scatter screenshots permanently. Recreating it here
    /// makes macOS resume using it.
    ///
    /// Only called from `start()`, i.e. at launch or when the setting is
    /// switched on. Doing it on every change event would mean deleting the
    /// folder in Finder saw it reappear instantly, which would feel like the
    /// app fighting the user.
    @discardableResult
    static func ensureConfiguredDirectoryExists() -> URL? {
        guard let url = configuredScreenshotPath() else { return nil }
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            // A file sitting where the folder should be: leave it alone rather
            // than destroying something the user may care about.
            return isDirectory.boolValue ? url : nil
        }

        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return configuredScreenshotDirectory()
    }

    static var desktopDirectory: URL? {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    /// Name of the folder created for screenshots on first launch.
    static let defaultFolderName = "Screenshots"

    private static let didConfigureDefaultFolderKey = "didConfigureDefaultScreenshotFolder"

    /// On first launch, give screenshots a dedicated folder instead of letting
    /// them pile up on the Desktop.
    ///
    /// Creates `~/Desktop/Screenshots` and points macOS at it — but only when
    /// the user has no screenshot location of their own, so an existing choice
    /// is never overwritten. Guarded to run exactly once, which means a user
    /// who later sets the location back to the Desktop keeps that decision
    /// rather than having it undone on every launch.
    ///
    /// Caveat worth knowing: macOS does not always adopt an externally written
    /// screenshot location straight away — it can take a logout, or the user
    /// opening ⌘⇧5 → Options. That's harmless here, because the new folder and
    /// the Desktop are both watched, so captures are picked up either way.
    static func performFirstRunSetupIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didConfigureDefaultFolderKey) else { return }
        // Mark it done up front: a failure below shouldn't mean retrying — and
        // re-prompting for Desktop access — on every subsequent launch.
        defaults.set(true, forKey: didConfigureDefaultFolderKey)

        // Someone who already picked a folder keeps it.
        guard configuredScreenshotPath() == nil,
              let desktop = desktopDirectory else { return }

        let folder = desktop.appendingPathComponent(defaultFolderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
        } catch {
            // Desktop access refused. Leave the system setting alone rather
            // than aiming macOS at a folder that doesn't exist.
            return
        }

        UserDefaults(suiteName: "com.apple.screencapture")?
            .set(folder.path, forKey: "location")
    }

    /// Every folder a screenshot might plausibly land in, most specific first
    /// and de-duplicated by path.
    static func candidateDirectories() -> [URL] {
        var seen: Set<String> = []
        return [configuredScreenshotDirectory(), desktopDirectory]
            .compactMap { $0 }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    // MARK: - Lifecycle

    func start() {
        guard !didAttempt else { return }
        didAttempt = true
        failureMessages = []

        // Set up the dedicated folder on first launch, then make sure whatever
        // folder is configured exists before we try to watch it.
        Self.performFirstRunSetupIfNeeded()
        Self.ensureConfiguredDirectoryExists()
        syncWatches()
    }

    func stop() {
        watches.forEach { $0.source?.cancel() }
        watches = []
        failureMessages = []
        failedPaths = []
        // Allow one fresh attempt if the user toggles the setting back on —
        // by then they may have granted access in System Settings.
        didAttempt = false
    }

    /// Adds watches for any candidate folder not already covered.
    ///
    /// Re-run after every change event, because the screenshot folder can be
    /// created, deleted and re-created at will. Directory events are *not*
    /// recursive, so a folder appearing inside the Desktop would otherwise go
    /// unwatched until the next launch — and since macOS would start writing
    /// screenshots into it immediately, they'd silently stop being captured.
    private func syncWatches() {
        let alreadyWatched = Set(watches.map(\.directory.standardizedFileURL.path))
        for directory in Self.candidateDirectories()
        where !alreadyWatched.contains(directory.standardizedFileURL.path) {
            if let watch = makeWatch(for: directory) {
                watches.append(watch)
            }
        }
    }

    private func makeWatch(for directory: URL) -> Watch? {
        let path = directory.standardizedFileURL.path
        guard !failedPaths.contains(path) else { return nil }

        // O_EVTONLY opens the directory for event monitoring only, without
        // reading its contents, and is the single permission check for this
        // folder for the whole session.
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            failedPaths.insert(path)
            failureMessages.append("No access to \(directory.lastPathComponent)")
            return nil
        }

        let watch = Watch(directory: directory)
        // Seed from the current contents so files already sitting in the folder
        // aren't captured retroactively.
        watch.knownFilenames = Self.filenames(in: directory)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self, weak watch] in
            // The queue is explicitly `.main`, so this is main-actor work.
            MainActor.assumeIsolated {
                guard let self, let watch else { return }
                self.handleChange(source.data, for: watch)
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        watch.source = source
        source.resume()
        return watch
    }

    private func handleChange(_ events: DispatchSource.FileSystemEvent, for watch: Watch) {
        // The folder was replaced or became unreachable; the descriptor now
        // refers to nothing useful, so drop this watch rather than spin on it.
        if events.contains(.delete) || events.contains(.revoke) || events.contains(.rename) {
            watch.source?.cancel()
            watch.source = nil
            watches.removeAll { $0 === watch }
            // Deleting the screenshot folder makes macOS fall back to the
            // Desktop, so make sure that fallback is covered.
            syncWatches()
            return
        }

        let current = Self.filenames(in: watch.directory)
        let added = current.subtracting(watch.knownFilenames)
        watch.knownFilenames = current

        for filename in added
        where ClipboardManager.imageExtensions.contains(
            (filename as NSString).pathExtension.lowercased()
        ) {
            onNewScreenshot(watch.directory.appendingPathComponent(filename))
        }

        // A new subfolder may be the screenshot folder being re-created.
        syncWatches()
    }

    private static func filenames(in directory: URL) -> Set<String> {
        guard let files = try? FileManager.default
            .contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return Set(files)
    }
}
