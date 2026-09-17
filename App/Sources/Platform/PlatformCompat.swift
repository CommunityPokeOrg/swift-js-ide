import Foundation
import EditorCore

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#else
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#endif

extension PlatformColor {
    convenience init(_ palette: PaletteColor) {
        self.init(red: palette.r, green: palette.g, blue: palette.b, alpha: palette.a)
    }
}

/// Applies tokenizer output to an `NSTextStorage`, shared by the macOS and iPadOS
/// editor backends (both use the TextKit 1 `NSLayoutManager` stack).
enum SyntaxHighlighter {

    static func apply(to storage: NSTextStorage, source: String,
                      palette: ThemePalette, font: PlatformFont) {
        let tokens = JSTokenizer().tokenize(source)
        let full = NSRange(location: 0, length: (source as NSString).length)
        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: PlatformColor(palette.text)
        ], range: full)
        for token in tokens {
            let range = NSRange(token.range, in: source)
            guard range.location + range.length <= full.length else { continue }
            storage.addAttribute(.foregroundColor,
                                 value: PlatformColor(palette.color(for: token.kind)),
                                 range: range)
        }
        storage.endEditing()
    }
}
