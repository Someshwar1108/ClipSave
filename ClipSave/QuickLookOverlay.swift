import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Spacebar preview for an image clip.
///
/// Deliberately not `QLPreviewPanel`: real Quick Look previews a file on disk,
/// and clip images live in memory. It also insists on an active app, which the
/// non-activating hotkey panel isn't.
struct QuickLookOverlay: View {
    let data: Data
    let pixelSize: NSSize?
    let onCopy: () -> Void
    let onDismiss: () -> Void

    private var image: NSImage? {
        ThumbnailCache.shared.fullImage(for: data)
    }

    private var dimensionText: String? {
        guard let pixelSize, pixelSize.width > 0 else { return nil }
        return "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
    }

    private var detailText: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        if let dimensionText { return "\(dimensionText) · \(size) · PNG" }
        return "\(size) · PNG"
    }

    var body: some View {
        ZStack {
            // Click-off to dismiss, matching how Quick Look behaves.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 272, maxHeight: 200)
                } else {
                    // A clip can outlive its decodability if the PNG was
                    // truncated on disk; say so instead of showing a blank box.
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                        Text("Can't preview this image")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 272, height: 140)
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screenshot")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(detailText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Button("Copy", action: onCopy)
                    Button("Save…", action: save)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
            }
            .frame(width: 272)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        }
        .transition(.opacity)
    }

    private func save() {
        // The hotkey panel is non-activating, so the save sheet would open
        // behind everything unless the app is promoted first.
        let delegate = AppDelegate.shared
        delegate?.enterForeground(reason: "quicklook-save")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot.png"
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url, options: .atomic)
            }
            delegate?.exitForeground(reason: "quicklook-save")
            onDismiss()
        }
    }
}
