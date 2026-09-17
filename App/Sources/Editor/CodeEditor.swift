import SwiftUI
import EditorCore

#if os(macOS)
import AppKit

/// SwiftUI wrapper around `LineNumberedTextView` (NSTextView) for macOS.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var palette: ThemePalette
    var revealRequest: RevealRequest?

    static let font = PlatformFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Explicit TextKit 1 stack — guarantees `layoutManager` exists for the
        // gutter renderer (a nil container creates the stack lazily on macOS).
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        // A zero-width container lays out degenerate glyphs — text computes
        // bounding rects but paints nothing.
        textContainer.containerSize = NSSize(
            width: 640, height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)

        let textView = LineNumberedTextView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            textContainer: textContainer
        )
        textView.palette = palette
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.insertionPointColor = PlatformColor(palette.text)
        textView.textColor = PlatformColor(palette.text)
        textView.backgroundColor = PlatformColor(palette.background)
        textView.drawsBackground = true
        textView.typingAttributes = [
            .font: Self.font,
            .foregroundColor: PlatformColor(palette.text)
        ]

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRulerView(textView: textView,
                                                          scrollView: scrollView)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = PlatformColor(palette.background)

        context.coordinator.textView = textView
        context.coordinator.setText(text, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            context.coordinator.setText(text, in: textView)
        }
        if let request = revealRequest, request != context.coordinator.lastReveal {
            context.coordinator.lastReveal = request
            textView.scrollToLine(request.line)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.textView?.delegate = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: LineNumberedTextView?
        var lastReveal: RevealRequest?
        private var isApplyingExternalChange = false

        init(_ parent: CodeEditor) { self.parent = parent }

        func setText(_ text: String, in textView: LineNumberedTextView) {
            isApplyingExternalChange = true
            let selected = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selected.location,
                                                          (text as NSString).length), length: 0))
            textView.recomputeNewlines()
            refreshHighlight(in: textView)
            isApplyingExternalChange = false
        }

        func refreshHighlight(in textView: LineNumberedTextView) {
            guard let storage = textView.textStorage else { return }
            SyntaxHighlighter.apply(to: storage, source: textView.string,
                                    palette: textView.palette, font: CodeEditor.font)
            textView.typingAttributes = [
                .font: CodeEditor.font,
                .foregroundColor: PlatformColor(textView.palette.text)
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange, let textView else { return }
            textView.recomputeNewlines()
            refreshHighlight(in: textView)
            parent.text = textView.string
        }
    }
}
#else
import UIKit

/// SwiftUI wrapper around `LineNumberedTextView` (UITextView) for iPadOS.
/// Built on an explicit TextKit 1 stack so the TextKit-1 `layoutManager`
/// used by the gutter rendering is guaranteed to exist.
struct CodeEditor: UIViewRepresentable {
    @Binding var text: String
    var palette: ThemePalette
    var revealRequest: RevealRequest?

    static let font = PlatformFont.monospacedSystemFont(ofSize: 15, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> LineNumberedTextView {
        // Explicit TextKit 1 stack → UITextView.layoutManager stays available.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)

        let textView = LineNumberedTextView(frame: .zero, textContainer: textContainer)
        textView.palette = palette
        textView.delegate = context.coordinator
        textView.font = Self.font
        textView.backgroundColor = PlatformColor(palette.background)
        textView.textColor = PlatformColor(palette.text)
        textView.tintColor = PlatformColor(palette.text)
        textView.typingAttributes = [
            .font: Self.font,
            .foregroundColor: PlatformColor(palette.text)
        ]
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive

        context.coordinator.textView = textView
        context.coordinator.setText(text, in: textView)
        return textView
    }

    func updateUIView(_ textView: LineNumberedTextView, context: Context) {
        if textView.text != text {
            context.coordinator.setText(text, in: textView)
        }
        if let request = revealRequest, request != context.coordinator.lastReveal {
            context.coordinator.lastReveal = request
            textView.scrollToLine(request.line)
        }
    }

    static func dismantleUIView(_ textView: LineNumberedTextView, coordinator: Coordinator) {
        coordinator.textView?.delegate = nil
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditor
        weak var textView: LineNumberedTextView?
        var lastReveal: RevealRequest?
        private var isApplyingExternalChange = false

        init(_ parent: CodeEditor) { self.parent = parent }

        func setText(_ text: String, in textView: LineNumberedTextView) {
            isApplyingExternalChange = true
            let selected = textView.selectedRange
            textView.text = text
            textView.selectedRange = NSRange(location: min(selected.location,
                                                         (text as NSString).length), length: 0)
            textView.recomputeNewlines()
            refreshHighlight(in: textView)
            isApplyingExternalChange = false
        }

        func refreshHighlight(in textView: LineNumberedTextView) {
            SyntaxHighlighter.apply(to: textView.textStorage, source: textView.text,
                                    palette: textView.palette, font: CodeEditor.font)
            textView.typingAttributes = [
                .font: CodeEditor.font,
                .foregroundColor: PlatformColor(textView.palette.text)
            ]
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingExternalChange, let tv = self.textView else { return }
            tv.recomputeNewlines()
            refreshHighlight(in: tv)
            parent.text = tv.text
        }
    }
}
#endif
