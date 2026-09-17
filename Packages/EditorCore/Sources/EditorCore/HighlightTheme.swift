import Foundation

/// A platform-agnostic RGBA color. The UI layer converts these to UIColor/NSColor/SwiftUI Color.
public struct PaletteColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.r = Double((hex >> 16) & 0xFF) / 255
        self.g = Double((hex >> 8) & 0xFF) / 255
        self.b = Double(hex & 0xFF) / 255
        self.a = alpha
    }
}

/// Colors for every semantic element of the editor surface.
public struct ThemePalette: Sendable {
    public var text: PaletteColor
    public var background: PaletteColor
    public var gutterText: PaletteColor
    public var gutterBackground: PaletteColor
    public var selection: PaletteColor
    public var tokenColors: [JSTokenKind: PaletteColor]

    public init(text: PaletteColor, background: PaletteColor, gutterText: PaletteColor,
                gutterBackground: PaletteColor, selection: PaletteColor,
                tokenColors: [JSTokenKind: PaletteColor]) {
        self.text = text
        self.background = background
        self.gutterText = gutterText
        self.gutterBackground = gutterBackground
        self.selection = selection
        self.tokenColors = tokenColors
    }

    public func color(for kind: JSTokenKind) -> PaletteColor {
        tokenColors[kind] ?? text
    }
}

public enum HighlightTheme {
    /// Dark palette loosely inspired by Xcode's default dark theme.
    public static let dark = ThemePalette(
        text: PaletteColor(hex: 0xD9D9D9),
        background: PaletteColor(hex: 0x1F1F24),
        gutterText: PaletteColor(hex: 0x6C7986),
        gutterBackground: PaletteColor(hex: 0x1F1F24),
        selection: PaletteColor(hex: 0x515C70, alpha: 0.5),
        tokenColors: [
            .keyword: PaletteColor(hex: 0xFC5FA3),
            .builtin: PaletteColor(hex: 0xD0A8FF),
            .number: PaletteColor(hex: 0xD9C97C),
            .string: PaletteColor(hex: 0xFC6A5D),
            .templateString: PaletteColor(hex: 0xFC6A5D),
            .regex: PaletteColor(hex: 0xE5C07B),
            .comment: PaletteColor(hex: 0x6C7986),
            .operator: PaletteColor(hex: 0x9EF1DD),
            .punctuation: PaletteColor(hex: 0xD9D9D9),
            .identifier: PaletteColor(hex: 0xD9D9D9),
            .property: PaletteColor(hex: 0x67B7F4),
            .functionCall: PaletteColor(hex: 0x78C2B3)
        ]
    )

    /// Light palette loosely inspired by Xcode's default light theme.
    public static let light = ThemePalette(
        text: PaletteColor(hex: 0x262626),
        background: PaletteColor(hex: 0xFFFFFF),
        gutterText: PaletteColor(hex: 0xA6A6A6),
        gutterBackground: PaletteColor(hex: 0xF5F5F5),
        selection: PaletteColor(hex: 0xB3D7FF, alpha: 0.7),
        tokenColors: [
            .keyword: PaletteColor(hex: 0xAD3DA4),
            .builtin: PaletteColor(hex: 0x703DAA),
            .number: PaletteColor(hex: 0x1C00CF),
            .string: PaletteColor(hex: 0xC41A16),
            .templateString: PaletteColor(hex: 0xC41A16),
            .regex: PaletteColor(hex: 0x9B5A00),
            .comment: PaletteColor(hex: 0x707F8C),
            .operator: PaletteColor(hex: 0x3E8087),
            .punctuation: PaletteColor(hex: 0x262626),
            .identifier: PaletteColor(hex: 0x262626),
            .property: PaletteColor(hex: 0x0F68A0),
            .functionCall: PaletteColor(hex: 0x326D74)
        ]
    )
}
