import SwiftUI

/// The one and only place a hex string becomes a colour.
///
/// Theme and stock JSON decodes into `HexColor`; view code reads
/// `theme.ink` and friends. A `Color(red:green:blue:)` or a `#` literal
/// anywhere in `Features/` is a bug.
struct HexColor: Hashable, Sendable {
    /// Components in the extended sRGB range, 0...1.
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Accepts `RGB`, `RGBA`, `RRGGBB` and `RRGGBBAA`, with or without a
    /// leading `#`. Returns nil for anything else so a typo in a theme file
    /// surfaces as a decoding error rather than a silent black.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.allSatisfy(\.isHexDigit) else { return nil }

        let characters = Array(text)
        switch characters.count {
        case 3, 4:
            // Shorthand: each digit is doubled, so `F` means `FF`.
            self.init(hex: String(characters.flatMap { [$0, $0] }))
        case 6, 8:
            let bytes = stride(from: 0, to: characters.count, by: 2).compactMap {
                UInt8(String(characters[$0..<($0 + 2)]), radix: 16)
            }
            guard bytes.count == characters.count / 2 else { return nil }
            self.init(
                red: Double(bytes[0]) / 255,
                green: Double(bytes[1]) / 255,
                blue: Double(bytes[2]) / 255,
                alpha: bytes.count == 4 ? Double(bytes[3]) / 255 : 1
            )
        default:
            return nil
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexString: String {
        func byte(_ value: Double) -> Int { Int((value * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha < 1 ? base + String(format: "%02X", byte(alpha)) : base
    }
}

// MARK: - Manipulation

extension HexColor {
    /// WCAG relative luminance. Used to decide which way "more contrast" points
    /// without the theme having to declare whether it is light or dark.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var isDark: Bool { relativeLuminance < 0.5 }

    func mixed(with other: HexColor, amount: Double) -> HexColor {
        let t = min(max(amount, 0), 1)
        return HexColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    func withAlpha(_ value: Double) -> HexColor {
        HexColor(red: red, green: green, blue: blue, alpha: min(max(value, 0), 1))
    }

    static let black = HexColor(red: 0, green: 0, blue: 0)
    static let white = HexColor(red: 1, green: 1, blue: 1)

    /// Pushes a colour away from the given background. Drives Increase Contrast
    /// without any theme needing a second hand-authored palette.
    func pushedAway(from background: HexColor, by amount: Double) -> HexColor {
        mixed(with: background.isDark ? .white : .black, amount: amount)
    }
}

// MARK: - Codable

extension HexColor: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let parsed = HexColor(hex: string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "“\(string)” is not a valid hex colour."
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

extension Color {
    /// Convenience for the rare non-theme case (asset-catalog parity, previews).
    /// Everything user-facing should reach for a theme token instead.
    init?(hex: String) {
        guard let parsed = HexColor(hex: hex) else { return nil }
        self = parsed.color
    }
}
