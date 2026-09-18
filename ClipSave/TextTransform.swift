import Foundation

/// Non-destructive text transforms offered in a clip's context menu.
///
/// A transform writes its result to the pasteboard and leaves the stored clip
/// untouched — the history stays a faithful record of what was actually copied.
nonisolated enum TextTransform: String, CaseIterable, Identifiable, Sendable {
    case trimWhitespace
    case uppercase
    case lowercase
    case formatJSON
    case plainText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trimWhitespace: return "Trim Whitespace"
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .formatJSON: return "Format JSON"
        case .plainText: return "Copy as Plain Text"
        }
    }

    /// The transformed text, or `nil` when this transform doesn't apply to the
    /// clip — either because the content is the wrong kind, or because the
    /// result would be identical to what's already stored. Menu items are built
    /// from this, so inapplicable transforms simply don't appear.
    func output(for content: ClipContent) -> String? {
        switch self {
        case .plainText:
            // Only meaningful for rich text: it's the one case where "copy the
            // text without its formatting" differs from a plain copy.
            guard case .richText(_, let plain) = content else { return nil }
            return plain

        case .trimWhitespace:
            guard let text = content.plainText else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == text ? nil : trimmed

        case .uppercase:
            guard let text = content.plainText else { return nil }
            let upper = text.localizedUppercase
            return upper == text ? nil : upper

        case .lowercase:
            guard let text = content.plainText else { return nil }
            let lower = text.localizedLowercase
            return lower == text ? nil : lower

        case .formatJSON:
            guard let text = content.plainText else { return nil }
            return Self.prettyPrintedJSON(text)
        }
    }

    /// Pretty-prints a JSON object or array, or returns `nil` if the text isn't
    /// one. Keys come out sorted: `JSONSerialization` doesn't preserve document
    /// order, so sorting at least makes the output deterministic rather than
    /// arbitrary.
    private static func prettyPrintedJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cheap gate so we don't hand every copied sentence to the parser.
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: parsed,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let output = String(data: pretty, encoding: .utf8)
        else { return nil }

        return output == trimmed ? nil : output
    }
}
