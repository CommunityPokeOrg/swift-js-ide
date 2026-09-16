import Foundation
import EditorCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private extension Array where Element == Int {
    /// Index of the first element for which `predicate` does not hold —
    /// the count of leading elements satisfying it (the array is sorted).
    func partitioningIndex(where predicate: (Int) -> Bool) -> Int {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if predicate(self[mid]) { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

#if os(macOS)
/// NSTextView subclass paired with `LineNumberRulerView` for line numbers.
/// The ruler is the sanctioned AppKit path: it renders independently of the
/// text view's draw pass and scrolls with the document automatically.
final class LineNumberedTextView: NSTextView {
    var palette: ThemePalette = HighlightTheme.dark
    var newlineOffsets: [Int] = [0]

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        textContainerInset = NSSize(width: 6, height: 10)
        layoutManager?.allowsNonContiguousLayout = false
    }

    func recomputeNewlines() {
        let ns = string as NSString
        var offsets: [Int] = []
        for i in 0..<ns.length where ns.character(at: i) == 0x0A {
            offsets.append(i)
        }
        newlineOffsets = offsets
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    private func leadingWhitespaceOfCurrentLine() -> String {
        let ns = string as NSString
        var loc = selectedRange.location
        while loc > 0 {
            let ch = ns.character(at: loc - 1)
            if ch == 0x0A { break }
            loc -= 1
        }
        var end = loc
        var indent = ""
        while end < ns.length {
            let ch = ns.character(at: end)
            if ch == 0x20 { indent += " " } else if ch == 0x09 { indent += "\t" } else { break }
            end += 1
        }
        return indent
    }

    override func insertTab(_ sender: Any?) {
        insertText("    ", replacementRange: selectedRange)
    }

    override func insertNewline(_ sender: Any?) {
        insertText("\n" + leadingWhitespaceOfCurrentLine(), replacementRange: selectedRange)
    }

    func scrollToLine(_ line: Int) {
        let ns = string as NSString
        guard line >= 1 else { return }
        let offset = line == 1 ? 0 : (newlineOffsets.count >= line - 1 ? newlineOffsets[line - 2] + 1 : ns.length)
        let clamped = min(offset, ns.length)
        setSelectedRange(NSRange(location: clamped, length: 0))
        scrollRangeToVisible(NSRange(location: clamped, length: 0))
        window?.makeFirstResponder(self)
    }
}

/// Vertical ruler that paints line numbers for `LineNumberedTextView`.
final class LineNumberRulerView: NSRulerView {
    static let thickness: CGFloat = 46
    weak var observedTextView: LineNumberedTextView?

    init(textView: LineNumberedTextView, scrollView: NSScrollView) {
        observedTextView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.thickness
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static let debugLayout =
        ProcessInfo.processInfo.environment["POKEIDE_DEBUG_LAYOUT"] == "1"

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = observedTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        if Self.debugLayout {
            let msg = "[layout] tv.frame=\(textView.frame) tv.bounds=\(textView.bounds) "
                  + "tv.visible=\(textView.visibleRect) strLen=\(textView.string.count) "
                  + "container=\(textContainer.containerSize) isHidden=\(textView.isHidden) "
                  + "inClip=\(String(describing: textView.superview))\n"
            FileHandle.standardError.write(Data(msg.utf8))
        }
        let palette = textView.palette

        PlatformColor(palette.gutterBackground).setFill()
        rect.fill()

        let ns = textView.string as NSString
        guard ns.length > 0 else { return }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let firstVisibleChar = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        let lastVisibleChar = layoutManager.characterIndexForGlyph(at: NSMaxRange(glyphRange))

        var lineIndex = textView.newlineOffsets.partitioningIndex { $0 < firstVisibleChar }
        let lineCount = textView.newlineOffsets.count + 1

        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: PlatformColor(palette.gutterText)
        ]

        let origin = convert(NSPoint.zero, from: textView)

        while lineIndex < lineCount {
            let charOffset = lineIndex == 0 ? 0 : textView.newlineOffsets[lineIndex - 1] + 1
            if charOffset > lastVisibleChar || charOffset > ns.length { break }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charOffset, max(0, ns.length - 1)))
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 0),
                in: textContainer
            )
            let label = String(lineIndex + 1) as NSString
            let size = label.size(withAttributes: attributes)
            let x = Self.thickness - size.width - 6
            let y = glyphRect.origin.y + origin.y + textView.textContainerInset.height
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            lineIndex += 1
        }
    }
}
#else
/// UITextView subclass that paints a line-number gutter in the left
/// `textContainerInset` margin. Must be constructed on a TextKit 1 stack
/// (explicit NSTextStorage/NSLayoutManager/NSTextContainer) so `layoutManager`
/// is available.
final class LineNumberedTextView: UITextView {
    static let gutterWidth: CGFloat = 48
    var palette: ThemePalette = HighlightTheme.dark
    private var newlineOffsets: [Int] = []

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        textContainerInset = UIEdgeInsets(top: 10, left: Self.gutterWidth, bottom: 10, right: 8)
        keyboardType = .default
        autocapitalizationType = .none
        autocorrectionType = .no
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
    }

    func recomputeNewlines() {
        let ns = text as NSString
        var offsets: [Int] = []
        for i in 0..<ns.length where ns.character(at: i) == 0x0A {
            offsets.append(i)
        }
        newlineOffsets = offsets
    }

    private func leadingWhitespaceOfCurrentLine() -> String {
        let ns = text as NSString
        var loc = selectedRange.location
        while loc > 0 {
            let ch = ns.character(at: loc - 1)
            if ch == 0x0A { break }
            loc -= 1
        }
        var end = loc
        var indent = ""
        while end < ns.length {
            let ch = ns.character(at: end)
            if ch == 0x20 { indent += " " } else if ch == 0x09 { indent += "\t" } else { break }
            end += 1
        }
        return indent
    }

    override func insertText(_ text: String) {
        if text == "\t" {
            super.insertText("    ")
            return
        }
        if text == "\n" {
            super.insertText("\n" + leadingWhitespaceOfCurrentLine())
            return
        }
        super.insertText(text)
    }

    func scrollToLine(_ line: Int) {
        let ns = text as NSString
        guard line >= 1 else { return }
        let offset = line == 1 ? 0 : (newlineOffsets.count >= line - 1 ? newlineOffsets[line - 2] + 1 : ns.length)
        let clamped = min(offset, ns.length)
        selectedRange = NSRange(location: clamped, length: 0)
        scrollRangeToVisible(NSRange(location: clamped, length: 0))
        becomeFirstResponder()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let gutterRect = CGRect(x: bounds.minX, y: bounds.minY,
                                width: Self.gutterWidth, height: bounds.height)
        PlatformColor(palette.gutterBackground).setFill()
        UIRectFill(gutterRect)
        PlatformColor(palette.gutterText).withAlphaComponent(0.4).setFill()
        UIRectFill(CGRect(x: bounds.minX + Self.gutterWidth - 1, y: bounds.minY,
                          width: 1, height: bounds.height))

        drawLineNumbers()
    }

    private func drawLineNumbers() {
        // UITextView.layoutManager/textContainer are non-optional.
        let layoutManager = self.layoutManager
        let textContainer = self.textContainer
        let ns = text as NSString
        let lineCount = newlineOffsets.count + 1
        let visibleRect = bounds

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let firstVisibleChar = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        let lastVisibleChar = layoutManager.characterIndexForGlyph(at: NSMaxRange(glyphRange))

        var lineIndex = newlineOffsets.partitioningIndex { $0 < firstVisibleChar }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.monospacedSystemFont(ofSize: max(11, (font?.pointSize ?? 14) - 2), weight: .regular),
            .foregroundColor: PlatformColor(palette.gutterText)
        ]

        while lineIndex < lineCount {
            let charOffset = lineIndex == 0 ? 0 : newlineOffsets[lineIndex - 1] + 1
            if charOffset > lastVisibleChar || charOffset > ns.length { break }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charOffset, max(0, ns.length - 1)))
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 0),
                in: textContainer
            )
            let label = String(lineIndex + 1) as NSString
            let size = label.size(withAttributes: attributes)
            let x = bounds.minX + Self.gutterWidth - size.width - 8
            let y = rect.origin.y + textContainerInset.top
            label.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            lineIndex += 1
        }
    }
}
#endif
