import Foundation

/// Optional on-disk persistence for temporary clips, so the history survives
/// quitting and restarting.
///
/// Images are written as sidecar PNG files named by content hash rather than
/// base64-inlined into the JSON. That keeps the index file small enough to
/// encode on the main thread, de-duplicates identical screenshots for free,
/// and means a corrupt image can't take the whole history down with it.
@MainActor
final class TempHistoryStore {
    static let shared = TempHistoryStore()

    private struct StoredClip: Codable {
        let id: UUID
        let timestamp: Date
        let hash: String
        let kind: String
        var text: String?
        var rtf: Data?
        var imageFile: String?
        var filePath: String?
    }

    private struct ImagePayload: Sendable {
        let filename: String
        let data: Data
    }

    private var pendingSave: Task<Void, Never>?

    private init() {}

    // MARK: - Locations

    private nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("ClipSave", isDirectory: true)
    }

    private nonisolated static var indexFile: URL {
        directory.appendingPathComponent("temp-history.json")
    }

    private nonisolated static var imagesDirectory: URL {
        directory.appendingPathComponent("images", isDirectory: true)
    }

    // MARK: - Saving

    /// Coalesces bursts of clipboard activity into one write. Copying several
    /// things in quick succession is common, and each one would otherwise mean
    /// a full rewrite of the index.
    func scheduleSave(_ clips: [Clip]) {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            // Encode only once the burst has settled — this task is
            // main-actor-isolated, so building the snapshot here is safe and
            // saves re-encoding the whole list on every single keystroke-fast
            // clipboard change.
            let snapshot = self.encode(clips)
            await Self.write(snapshot)
        }
    }

    /// Writes immediately, for app termination where there's no time to debounce.
    func saveNow(_ clips: [Clip]) {
        pendingSave?.cancel()
        pendingSave = nil
        let snapshot = encode(clips)
        Self.writeSynchronously(snapshot)
    }

    private struct Snapshot: Sendable {
        let json: Data
        let images: [ImagePayload]
        let liveImageFiles: Set<String>
    }

    private func encode(_ clips: [Clip]) -> Snapshot {
        var stored: [StoredClip] = []
        var images: [ImagePayload] = []
        var liveFiles: Set<String> = []

        for clip in clips {
            var record = StoredClip(id: clip.id,
                                    timestamp: clip.timestamp,
                                    hash: clip.contentHash,
                                    kind: clip.content.kind)
            switch clip.content {
            case .text(let value):
                record.text = value
            case .richText(let data, let preview):
                record.rtf = data
                record.text = preview
            case .image(let data):
                let filename = "\(clip.contentHash).png"
                record.imageFile = filename
                liveFiles.insert(filename)
                images.append(ImagePayload(filename: filename, data: data))
            case .file(let url):
                record.filePath = url.path
            }
            stored.append(record)
        }

        // Encoding happens here, on the main actor, because the payload holds
        // no image bytes and is therefore cheap. Only file I/O goes off-thread.
        let json = (try? JSONEncoder().encode(stored)) ?? Data()
        return Snapshot(json: json, images: images, liveImageFiles: liveFiles)
    }

    private nonisolated static func write(_ snapshot: Snapshot) async {
        await Task.detached(priority: .utility) {
            writeSynchronously(snapshot)
        }.value
    }

    private nonisolated static func writeSynchronously(_ snapshot: Snapshot) {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        for payload in snapshot.images {
            let destination = imagesDirectory.appendingPathComponent(payload.filename)
            // Names are content hashes, so an existing file is already correct.
            guard !fm.fileExists(atPath: destination.path) else { continue }
            try? payload.data.write(to: destination, options: .atomic)
        }

        try? snapshot.json.write(to: indexFile, options: .atomic)

        // Drop sidecars for clips that have since expired or been deleted.
        if let existing = try? fm.contentsOfDirectory(atPath: imagesDirectory.path) {
            for filename in existing where !snapshot.liveImageFiles.contains(filename) {
                try? fm.removeItem(at: imagesDirectory.appendingPathComponent(filename))
            }
        }
    }

    // MARK: - Loading

    /// Reads the persisted history. Called once at launch, so it reads
    /// synchronously rather than making the first paint wait on a task.
    func load(maxImageBytes: Int) -> [Clip] {
        guard let data = try? Data(contentsOf: Self.indexFile),
              let stored = try? JSONDecoder().decode([StoredClip].self, from: data)
        else { return [] }

        return stored.compactMap { record in
            guard let content = Self.content(from: record, maxImageBytes: maxImageBytes)
            else { return nil }
            return Clip(id: record.id,
                        content: content,
                        timestamp: record.timestamp,
                        contentHash: record.hash)
        }
    }

    private nonisolated static func content(from record: StoredClip,
                                            maxImageBytes: Int) -> ClipContent? {
        switch record.kind {
        case "text":
            guard let text = record.text else { return nil }
            return .text(text)

        case "richText":
            guard let rtf = record.rtf else { return nil }
            return .richText(rtf, record.text ?? "")

        case "image":
            guard let filename = record.imageFile,
                  let data = try? Data(contentsOf: imagesDirectory
                      .appendingPathComponent(filename)),
                  // Honour the *current* size limit: the user may have lowered
                  // it since these clips were captured.
                  data.count <= maxImageBytes
            else { return nil }
            return .image(data)

        case "file":
            guard let path = record.filePath else { return nil }
            return .file(URL(fileURLWithPath: path))

        default:
            return nil
        }
    }

    // MARK: - Clearing

    /// Removes everything on disk, for when the user turns persistence off.
    func clear() {
        pendingSave?.cancel()
        pendingSave = nil
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: Self.indexFile)
            try? FileManager.default.removeItem(at: Self.imagesDirectory)
        }
    }
}
