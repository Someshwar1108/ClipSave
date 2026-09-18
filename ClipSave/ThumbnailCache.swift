import AppKit
import CryptoKit
import Foundation
import ImageIO

/// Content fingerprints used for de-duplication, thumbnail cache keys, and
/// on-disk image filenames.
///
/// SHA-256 rather than `Hasher`: `Hasher`'s seed is randomised per process, so
/// a fingerprint written to disk in one launch would not match the same clip in
/// the next — and both permanent clips and (optionally) temporary clips persist.
enum ContentHash {
    nonisolated static func hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func hex(of string: String) -> String {
        hex(of: Data(string.utf8))
    }
}

/// A decoded row thumbnail plus the original pixel dimensions, kept together so
/// a row can draw itself without ever touching the full-size image.
final class ThumbnailEntry: NSObject {
    let image: NSImage
    let pixelSize: NSSize

    init(image: NSImage, pixelSize: NSSize) {
        self.image = image
        self.pixelSize = pixelSize
    }
}

/// Downscaled row thumbnails, keyed by clip content hash.
///
/// v3.4 called `NSImage(data:)` inside `ClipRow.body`, so every scroll frame
/// re-decoded every visible screenshot from PNG. Caching the *downscaled*
/// result also bounds memory: a 60×60 thumbnail is a few KB, where the decoded
/// full-size bitmap of a 4K screenshot is roughly 35 MB.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Matches the row thumbnail frame in `ClipRow`.
    static let rowSize = NSSize(width: 60, height: 60)

    /// Longest side of the hover preview. Matches the popover's display box, so
    /// the preview is sharp on Retina without ever decoding the full bitmap —
    /// a 2940×1912 screenshot inflates to roughly 22 MB.
    static let previewMaxSide: CGFloat = 480

    private let cache = NSCache<NSString, ThumbnailEntry>()

    private init() {
        // Bounded by count rather than bytes; entries are uniformly tiny.
        cache.countLimit = 200
    }

    func entry(for data: Data, key: String) -> ThumbnailEntry? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let made = Self.makeEntry(from: data,
                                        boxSide: Self.rowSize.width,
                                        fillsBox: true) else { return nil }
        cache.setObject(made, forKey: key as NSString)
        return made
    }

    /// Mid-size image for the hover preview, cached separately from the row
    /// thumbnail so hovering doesn't evict it or re-decode on every pass.
    func preview(for data: Data, key: String) -> NSImage? {
        let previewKey = "\(key):preview" as NSString
        if let cached = cache.object(forKey: previewKey) { return cached.image }
        guard let made = Self.makeEntry(from: data,
                                        boxSide: Self.previewMaxSide,
                                        fillsBox: false) else { return nil }
        cache.setObject(made, forKey: previewKey)
        return made.image
    }

    /// Full-resolution image, for Quick Look only. Deliberately uncached — one
    /// 4K bitmap outweighs the entire thumbnail cache.
    func fullImage(for data: Data) -> NSImage? {
        NSImage(data: data)
    }

    /// Builds the thumbnail through ImageIO, which decodes only the pixels it
    /// needs instead of inflating the whole image first.
    private static func makeEntry(from data: Data,
                                  boxSide: CGFloat,
                                  fillsBox: Bool) -> ThumbnailEntry? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0

        // Rows use scaledToFill, so the *short* side has to reach the box: ask
        // for a long side scaled by the aspect ratio, capped so a panorama
        // can't request an enormous thumbnail. The hover preview uses
        // scaledToFit instead, where the long side already governs.
        let longSide = max(pixelWidth, pixelHeight)
        let shortSide = max(min(pixelWidth, pixelHeight), 1)
        let aspect = fillsBox ? min(longSide / shortSide, 4) : 1
        let screenScale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixelSize = boxSide * screenScale * aspect

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cgThumb,
                            size: NSSize(width: cgThumb.width, height: cgThumb.height))
        // Fall back to the thumbnail's own size if the metadata was missing.
        let reported = pixelWidth > 0 && pixelHeight > 0
            ? NSSize(width: pixelWidth, height: pixelHeight)
            : NSSize(width: cgThumb.width, height: cgThumb.height)
        return ThumbnailEntry(image: image, pixelSize: reported)
    }
}
