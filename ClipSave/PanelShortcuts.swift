import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A shortcut that only fires while the ClipSave panel is focused.
///
/// Deliberately *not* `KeyCombo`: that type speaks Carbon's vocabulary because
/// `RegisterEventHotKey` requires it. In-panel shortcuts go through SwiftUI's
/// `.keyboardShortcut`, which wants a `KeyEquivalent` and `EventModifiers`.
/// They also differ in kind — a bare `↑` or `Space` is perfectly reasonable
/// here, whereas a global hotkey without a modifier would be swallowed
/// system-wide.
/// `nonisolated` because the target defaults to `MainActor` isolation, which
/// would otherwise give this plain value type a main-actor-isolated `Hashable`
/// conformance — unusable from nonisolated code, and an error under the Swift 6
/// language mode.
nonisolated struct LocalShortcut: Codable, Hashable, Sendable {
    /// Either a single character, or one of the named keys below.
    let key: String
    /// Raw value of `SwiftUI.EventModifiers`.
    ///
    /// Qualified throughout: `Carbon.HIToolbox` declares an `EventModifiers`
    /// of its own, so the bare name is ambiguous in this file.
    let modifiersRaw: Int

    init(key: String, modifiers: SwiftUI.EventModifiers = []) {
        self.key = key
        self.modifiersRaw = modifiers.rawValue
    }

    var modifiers: SwiftUI.EventModifiers {
        SwiftUI.EventModifiers(rawValue: modifiersRaw)
    }

    // MARK: Named keys

    private static let namedKeys: [String: (KeyEquivalent, String)] = [
        "up": (.upArrow, "↑"),
        "down": (.downArrow, "↓"),
        "left": (.leftArrow, "←"),
        "right": (.rightArrow, "→"),
        "return": (.return, "↩"),
        "delete": (.delete, "⌫"),
        "forwardDelete": (.deleteForward, "⌦"),
        "space": (.space, "Space"),
        "escape": (.escape, "⎋"),
        "tab": (.tab, "⇥"),
        "home": (.home, "↖"),
        "end": (.end, "↘"),
        "pageUp": (.pageUp, "⇞"),
        "pageDown": (.pageDown, "⇟")
    ]

    var keyEquivalent: KeyEquivalent {
        if let named = Self.namedKeys[key] { return named.0 }
        return KeyEquivalent(key.first ?? " ")
    }

    /// Glyphs in the macOS convention: ⌃ ⌥ ⇧ ⌘, then the key.
    var display: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        let label = Self.namedKeys[key]?.1 ?? key.uppercased()
        return symbols + label
    }

    /// Builds a shortcut from a recorded key-down event.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: SwiftUI.EventModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        let named: [Int: String] = [
            kVK_UpArrow: "up", kVK_DownArrow: "down",
            kVK_LeftArrow: "left", kVK_RightArrow: "right",
            kVK_Return: "return", kVK_Delete: "delete",
            kVK_ForwardDelete: "forwardDelete", kVK_Space: "space",
            kVK_Escape: "escape", kVK_Tab: "tab",
            kVK_Home: "home", kVK_End: "end",
            kVK_PageUp: "pageUp", kVK_PageDown: "pageDown"
        ]

        if let name = named[Int(event.keyCode)] {
            self.init(key: name, modifiers: modifiers)
            return
        }

        guard let character = event.charactersIgnoringModifiers?.lowercased().first,
              character.isLetter || character.isNumber
                || character.isPunctuation || character.isSymbol
        else { return nil }
        self.init(key: String(character), modifiers: modifiers)
    }
}

/// The in-panel actions whose shortcuts can be reassigned.
///
/// `⌘1`–`⌘9` and `⌘,` are deliberately absent: the first is a nine-key
/// sequence that isn't meaningfully rebindable one key at a time, and the
/// second is the system-wide convention for opening Settings.
nonisolated enum PanelAction: String, CaseIterable, Identifiable, Sendable {
    case focusSearch
    case moveUp
    case moveDown
    case copyAndClose
    case deleteClip
    case quickLook
    case formatJSON
    case close

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focusSearch: return "Focus the search bar"
        case .moveUp: return "Move selection up"
        case .moveDown: return "Move selection down"
        case .copyAndClose: return "Copy selected clip and close"
        case .deleteClip: return "Remove the selected clip"
        case .quickLook: return "Quick Look the selected image"
        case .formatJSON: return "Format as JSON and copy"
        case .close: return "Close Quick Look, then ClipSave"
        }
    }

    var defaultShortcut: LocalShortcut {
        switch self {
        case .focusSearch: return LocalShortcut(key: "f", modifiers: .command)
        case .moveUp: return LocalShortcut(key: "up")
        case .moveDown: return LocalShortcut(key: "down")
        case .copyAndClose: return LocalShortcut(key: "return")
        case .deleteClip: return LocalShortcut(key: "delete")
        case .quickLook: return LocalShortcut(key: "space")
        case .formatJSON: return LocalShortcut(key: "j", modifiers: [.command, .shift])
        case .close: return LocalShortcut(key: "escape")
        }
    }
}

/// Click-to-record field for an in-panel shortcut.
///
/// Unlike the global recorder this accepts bare keys, because a shortcut that
/// only applies inside a focused panel can safely be a single keypress.
struct PanelShortcutRecorder: View {
    @Binding var shortcut: LocalShortcut

    /// Applies the shortcut. Returns a message when it clashes with another
    /// ClipSave action, in which case the previous value stays.
    let commit: (LocalShortcut) -> String?

    @State private var isRecording = false
    @State private var isHovering = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                HStack(spacing: 5) {
                    Text(isRecording ? "Press keys…" : shortcut.display)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    if !isRecording {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    }
                }
                .frame(minWidth: 72)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording
                              ? Color.accentColor.opacity(0.25)
                              : Color.primary.opacity(isHovering ? 0.18 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording || isHovering
                                      ? Color.accentColor
                                      : Color.primary.opacity(0.18),
                                      lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help("Click, then press the key you want")

            if let errorMessage, !isRecording {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow it, so recording can't trigger anything else
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        // Escape cancels recording rather than being recorded — otherwise
        // there's no way out of the field without assigning something.
        if event.keyCode == UInt16(kVK_Escape),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            stopRecording()
            return
        }
        guard let candidate = LocalShortcut(event: event) else {
            errorMessage = "Unsupported key"
            return
        }
        if let failure = commit(candidate) {
            errorMessage = failure
        } else {
            shortcut = candidate
            errorMessage = nil
        }
        stopRecording()
    }
}
