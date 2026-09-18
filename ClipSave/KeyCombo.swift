import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A global hotkey combination, stored in Carbon's vocabulary because that's
/// what `RegisterEventHotKey` speaks.
///
/// The human-readable `display` string is captured at record time rather than
/// derived later: mapping a virtual key code back to a label means consulting
/// the active keyboard layout, and the label would then silently change if the
/// user switched layouts after recording.
nonisolated struct KeyCombo: Equatable, Codable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    static let defaultCombo = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        display: "⌘⇧V"
    )

    /// Builds a combo from a recorded key-down event, or returns `nil` if the
    /// combination isn't usable as a global hotkey.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Require ⌘, ⌃ or ⌥. A bare key — or a mere ⇧+key — would be captured
        // system-wide and break typing in every other app.
        let hasPrimaryModifier = flags.contains(.command)
            || flags.contains(.control)
            || flags.contains(.option)
        guard hasPrimaryModifier else { return nil }

        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        let code = UInt32(event.keyCode)
        guard let label = Self.keyLabel(for: event) else { return nil }

        self.keyCode = code
        self.carbonModifiers = carbon
        // Glyph order follows the macOS convention: ⌃ ⌥ ⇧ ⌘, then the key.
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option)  { symbols += "⌥" }
        if flags.contains(.shift)   { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        self.display = symbols + label
    }

    private init(keyCode: UInt32, carbonModifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.display = display
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        if let named = namedKeys[Int(event.keyCode)] { return named }
        // Fall back to the character the key produces with modifiers ignored,
        // which is what the user sees printed on the keycap.
        guard let characters = event.charactersIgnoringModifiers,
              let first = characters.first,
              !first.isWhitespace,
              first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol
        else { return nil }
        return String(first).uppercased()
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]
}

/// Click-to-record field for the global shortcut.
///
/// While recording, a local key-down monitor swallows events so the keystroke
/// can't also trigger whatever it would normally do inside Settings.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?

    /// Offers a control to unassign the shortcut. The main hotkey opts out —
    /// clearing it would leave no way to open ClipSave from the keyboard.
    var allowsClearing: Bool = false

    /// Applies the combo, or unassigns it when `nil`. Returns an error message
    /// when the combination can't be used — typically because another app
    /// already holds it — in which case the previous value stays in force.
    let commit: (KeyCombo?) -> String?

    @State private var isRecording = false
    @State private var isHovering = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                // The pencil and the hover highlight exist to make it obvious
                // this is an editable control. Without them it reads as a
                // static label showing the current shortcut, and nobody
                // discovers that it can be clicked.
                HStack(spacing: 5) {
                    Text(isRecording ? "Press keys…" : (combo?.display ?? "Not set"))
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(combo == nil && !isRecording ? .secondary : .primary)
                    if !isRecording {
                        Image(systemName: "pencil")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    }
                }
                .frame(minWidth: 84)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
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
            .help("Click, then press the combination you want")

            if allowsClearing, combo != nil, !isRecording {
                Button {
                    if commit(nil) == nil {
                        combo = nil
                        errorMessage = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove this shortcut")
            }

            if isRecording {
                Text("⎋ to cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        errorMessage = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow it
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        guard let candidate = KeyCombo(event: event) else {
            errorMessage = "Include ⌘, ⌃ or ⌥."
            return
        }
        if let failure = commit(candidate) {
            errorMessage = failure
        } else {
            combo = candidate
            errorMessage = nil
        }
        stopRecording()
    }
}
