import AppKit
import SwiftUI

/// A colour literal recognised in a clip's text — `#FF5722`, `rgb(255, 87, 34)`,
/// `hsla(14, 100%, 57%, 0.5)` and friends.
///
/// Detection is deliberately whole-string: a paragraph that merely mentions a
/// hex code is still a text clip, otherwise prose would sprout swatches.
nonisolated struct DetectedColor: Equatable, Sendable, Codable {
    enum Notation: String, Sendable, Codable {
        case hex = "HEX"
        case rgb = "RGB"
        case hsl = "HSL"
    }

    /// Components in 0...1, sRGB.
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    let notation: Notation

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    private var bytes: (Int, Int, Int) {
        (Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var hexString: String {
        let (r, g, b) = bytes
        if alpha < 1 {
            let a = Int((alpha * 255).rounded())
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        let (r, g, b) = bytes
        if alpha < 1 {
            return "rgba(\(r), \(g), \(b), \(Self.number(alpha)))"
        }
        return "rgb(\(r), \(g), \(b))"
    }

    /// Integer components where they are exact, up to two decimals where they
    /// are not.
    ///
    /// Rounding hue and percentages to whole numbers shifts the colour by a
    /// shade — `#FF5722` came back as `#FF5724` — so "Copy as HSL" would hand
    /// the user a value that no longer matches what they copied.
    var hslString: String {
        let (h, s, l) = Self.toHSL(red: red, green: green, blue: blue)
        let hue = Self.number(h)
        let saturation = Self.number(s * 100)
        let lightness = Self.number(l * 100)
        if alpha < 1 {
            return "hsla(\(hue), \(saturation)%, \(lightness)%, \(Self.number(alpha)))"
        }
        return "hsl(\(hue), \(saturation)%, \(lightness)%)"
    }

    /// A well-known colour name, but only when the match is near-exact —
    /// labelling an arbitrary colour with the nearest name would be worse than
    /// showing no name at all.
    var name: String? {
        let (r, g, b) = bytes
        var best: (name: String, distance: Double)?
        for entry in Self.namedColors {
            let dr = Double(r - entry.r)
            let dg = Double(g - entry.g)
            let db = Double(b - entry.b)
            let distance = (dr * dr + dg * dg + db * db).squareRoot()
            if best == nil || distance < best!.distance {
                best = (entry.name, distance)
            }
        }
        guard let best, best.distance <= 10 else { return nil }
        return best.name
    }

    /// Subtitle shown under the value in a row, e.g. "Deep Orange · HEX".
    var subtitle: String {
        if let name { return "\(name) · \(notation.rawValue)" }
        return "sRGB · \(notation.rawValue)"
    }

    /// Black or white, whichever stays legible on top of this colour.
    var contrastingForeground: Color {
        // Rec. 709 relative luminance.
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.55 ? .black : .white
    }

    /// Rounds to two decimal places and drops any trailing zeros, so exact
    /// values print as plain integers.
    private static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%g", rounded)
    }

    private static func toHSL(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maxC {
        case red:   hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
        case green: hue = 60 * (((blue - red) / delta) + 2)
        default:    hue = 60 * (((red - green) / delta) + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, min(max(saturation, 0), 1), lightness)
    }
}

// MARK: - Parsing

// `nonisolated` for the same reason as the type itself: parsing is pure and
// gets called from `Clip`'s nonisolated initialisers and `Codable` conformance.
nonisolated extension DetectedColor {
    static func parse(_ raw: String) -> DetectedColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Longest legal form is roughly `hsla(360, 100%, 100%, 0.001)`; the cap
        // keeps us from scanning long text at all.
        guard !trimmed.isEmpty, trimmed.count <= 36 else { return nil }

        if trimmed.hasPrefix("#") {
            return parseHex(String(trimmed.dropFirst()))
        }
        if trimmed.hasPrefix("rgb") {
            return parseFunctional(trimmed, function: "rgb", notation: .rgb)
        }
        if trimmed.hasPrefix("hsl") {
            return parseFunctional(trimmed, function: "hsl", notation: .hsl)
        }
        return nil
    }

    private static func parseHex(_ digits: String) -> DetectedColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        // #RGB and #RGBA are shorthand: each digit is doubled.
        let expanded: String
        switch digits.count {
        case 3, 4: expanded = digits.map { "\($0)\($0)" }.joined()
        case 6, 8: expanded = digits
        default: return nil
        }

        let pairs = stride(from: 0, to: expanded.count, by: 2).map { offset -> Double in
            let start = expanded.index(expanded.startIndex, offsetBy: offset)
            let end = expanded.index(start, offsetBy: 2)
            return Double(UInt8(expanded[start..<end], radix: 16) ?? 0) / 255
        }
        guard pairs.count == 3 || pairs.count == 4 else { return nil }
        return DetectedColor(red: pairs[0], green: pairs[1], blue: pairs[2],
                             alpha: pairs.count == 4 ? pairs[3] : 1,
                             notation: .hex)
    }

    private static func parseFunctional(_ text: String,
                                        function: String,
                                        notation: Notation) -> DetectedColor? {
        // Accept both the `rgb()` and legacy `rgba()` spellings.
        var rest = String(text.dropFirst(function.count))
        if rest.hasPrefix("a") { rest.removeFirst() }
        guard rest.hasPrefix("("), rest.hasSuffix(")") else { return nil }
        rest = String(rest.dropFirst().dropLast())

        // CSS allows comma-separated and space-separated forms, with `/` before
        // the alpha in the modern syntax.
        let parts = rest
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
            .map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }

        let alpha = parts.count == 4 ? (unitValue(parts[3]) ?? 1) : 1

        switch notation {
        case .rgb:
            guard let r = channel(parts[0]),
                  let g = channel(parts[1]),
                  let b = channel(parts[2]) else { return nil }
            return DetectedColor(red: r, green: g, blue: b, alpha: alpha, notation: .rgb)

        case .hsl:
            guard let hue = angle(parts[0]),
                  let s = percentage(parts[1]),
                  let l = percentage(parts[2]) else { return nil }
            let (r, g, b) = fromHSL(hue: hue, saturation: s, lightness: l)
            return DetectedColor(red: r, green: g, blue: b, alpha: alpha, notation: .hsl)

        case .hex:
            return nil
        }
    }

    /// An RGB channel: `0...255`, or a percentage.
    private static func channel(_ token: String) -> Double? {
        if token.hasSuffix("%") { return percentage(token) }
        guard let value = Double(token), value >= 0, value <= 255 else { return nil }
        return value / 255
    }

    private static func percentage(_ token: String) -> Double? {
        guard token.hasSuffix("%"), let value = Double(token.dropLast()),
              value >= 0, value <= 100 else { return nil }
        return value / 100
    }

    /// Alpha: `0...1`, or a percentage.
    private static func unitValue(_ token: String) -> Double? {
        if token.hasSuffix("%") { return percentage(token) }
        guard let value = Double(token), value >= 0, value <= 1 else { return nil }
        return value
    }

    private static func angle(_ token: String) -> Double? {
        var text = token
        for suffix in ["deg", "grad", "rad", "turn"] where text.hasSuffix(suffix) {
            // Only plain degrees are supported; other units are rare enough
            // that refusing to guess is better than mis-rendering them.
            guard suffix == "deg" else { return nil }
            text = String(text.dropLast(suffix.count))
        }
        guard let value = Double(text) else { return nil }
        return value.truncatingRemainder(dividingBy: 360)
    }

    private static func fromHSL(hue: Double,
                                saturation: Double,
                                lightness: Double) -> (Double, Double, Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = ((hue < 0 ? hue + 360 : hue)) / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2

        let rgb: (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: rgb = (chroma, x, 0)
        case 1: rgb = (x, chroma, 0)
        case 2: rgb = (0, chroma, x)
        case 3: rgb = (0, x, chroma)
        case 4: rgb = (x, 0, chroma)
        default: rgb = (chroma, 0, x)
        }
        return (rgb.0 + match, rgb.1 + match, rgb.2 + match)
    }
}

// MARK: - Named colours

nonisolated extension DetectedColor {
    private struct Named {
        let name: String
        let r: Int, g: Int, b: Int
    }

    private static let namedColors: [Named] = [
        .init(name: "Black", r: 0, g: 0, b: 0),
        .init(name: "White", r: 255, g: 255, b: 255),
        .init(name: "Red", r: 255, g: 0, b: 0),
        .init(name: "Lime", r: 0, g: 255, b: 0),
        .init(name: "Blue", r: 0, g: 0, b: 255),
        .init(name: "Yellow", r: 255, g: 255, b: 0),
        .init(name: "Cyan", r: 0, g: 255, b: 255),
        .init(name: "Magenta", r: 255, g: 0, b: 255),
        .init(name: "Gray", r: 128, g: 128, b: 128),
        .init(name: "Silver", r: 192, g: 192, b: 192),
        .init(name: "Green", r: 0, g: 128, b: 0),
        .init(name: "Maroon", r: 128, g: 0, b: 0),
        .init(name: "Olive", r: 128, g: 128, b: 0),
        .init(name: "Teal", r: 0, g: 128, b: 128),
        .init(name: "Navy", r: 0, g: 0, b: 128),
        .init(name: "Purple", r: 128, g: 0, b: 128),
        .init(name: "Orange", r: 255, g: 165, b: 0),
        .init(name: "Pink", r: 255, g: 192, b: 203),
        .init(name: "Brown", r: 165, g: 42, b: 42),
        .init(name: "Gold", r: 255, g: 215, b: 0),
        .init(name: "Indigo", r: 75, g: 0, b: 130),
        .init(name: "Violet", r: 238, g: 130, b: 238),
        .init(name: "Coral", r: 255, g: 127, b: 80),
        .init(name: "Salmon", r: 250, g: 128, b: 114),
        .init(name: "Crimson", r: 220, g: 20, b: 60),
        .init(name: "Turquoise", r: 64, g: 224, b: 208),
        .init(name: "Tomato", r: 255, g: 99, b: 71),
        .init(name: "Slate Gray", r: 112, g: 128, b: 144),
        .init(name: "Sky Blue", r: 135, g: 206, b: 235),
        .init(name: "Steel Blue", r: 70, g: 130, b: 180),
        .init(name: "Forest Green", r: 34, g: 139, b: 34),
        .init(name: "Sea Green", r: 46, g: 139, b: 87),
        .init(name: "Khaki", r: 240, g: 230, b: 140),
        .init(name: "Lavender", r: 230, g: 230, b: 250),
        .init(name: "Plum", r: 221, g: 160, b: 221),
        .init(name: "Orchid", r: 218, g: 112, b: 214),
        .init(name: "Chocolate", r: 210, g: 105, b: 30),
        .init(name: "Tan", r: 210, g: 180, b: 140),
        .init(name: "Beige", r: 245, g: 245, b: 220),
        .init(name: "Ivory", r: 255, g: 255, b: 240),
        // Material palette — the most common source of pasted hex codes.
        .init(name: "Deep Orange", r: 255, g: 87, b: 34),
        .init(name: "Material Red", r: 244, g: 67, b: 54),
        .init(name: "Material Pink", r: 233, g: 30, b: 99),
        .init(name: "Material Purple", r: 156, g: 39, b: 176),
        .init(name: "Material Indigo", r: 63, g: 81, b: 181),
        .init(name: "Material Blue", r: 33, g: 150, b: 243),
        .init(name: "Material Cyan", r: 0, g: 188, b: 212),
        .init(name: "Material Teal", r: 0, g: 150, b: 136),
        .init(name: "Material Green", r: 76, g: 175, b: 80),
        .init(name: "Material Lime", r: 205, g: 220, b: 57),
        .init(name: "Material Amber", r: 255, g: 193, b: 7),
        .init(name: "Material Brown", r: 121, g: 85, b: 72),
        .init(name: "Material Blue Gray", r: 96, g: 125, b: 139)
    ]
}

// MARK: - Row presentation

/// The swatch + value + subtitle layout used for a colour clip in the list.
struct ColorClipPreview: View {
    let value: String
    let detected: DetectedColor

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(detected.color)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                )
                // A checkerboard would be overkill; a hairline is enough to
                // keep a translucent or near-background colour visible.
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                Text(detected.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
