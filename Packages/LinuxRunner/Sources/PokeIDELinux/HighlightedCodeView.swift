import Foundation
import SwiftCrossUI

import EditorCore

/// Renders source code with the shared `JSTokenizer` + `ThemePalette`:
/// a gutter of line numbers plus one colored `Text` span per token —
/// the same visual output the NSTextView/UITextView editor produces
/// through attributed strings.
struct HighlightedCodeView: View {
    let source: String
    let palette: ThemePalette
    /// Cap for very large files — this view is for snapshots, not a real editor.
    let maxLines = 400

    struct LineSpan {
        let text: String
        let color: Color
    }

    var lines: [[LineSpan]] {
        var lines: [[LineSpan]] = [[]]
        let tokens = JSTokenizer().tokenize(source)
        var cursor = source.startIndex
        for token in tokens {
            // Whitespace gap before this token — may open new lines.
            for ch in source[cursor..<token.range.lowerBound] where ch == "\n" {
                lines.append([])
            }
            let color = Self.color(for: token.kind, palette: palette)
            let parts = String(source[token.range]).components(separatedBy: "\n")
            for (index, part) in parts.enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty {
                    lines[lines.count - 1].append(LineSpan(text: part, color: color))
                }
            }
            cursor = token.range.upperBound
        }
        for ch in source[cursor...] where ch == "\n" {
            lines.append([])
        }
        return lines
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.prefix(maxLines).indices), id: \.self) { index in
                    HStack(alignment: .top, spacing: 0) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(Self.color(from: palette.gutterText))
                            .frame(width: 36, alignment: .trailing)
                        Text(" ")
                        Group {
                            if lines[index].isEmpty {
                                Text(" ")
                            } else {
                                HStack(spacing: 0) {
                                    ForEach(Array(lines[index].indices), id: \.self) { spanIndex in
                                        Text(lines[index][spanIndex].text)
                                            .font(.system(size: 13, design: .monospaced))
                                            .foregroundColor(lines[index][spanIndex].color)
                                    }
                                }
                            }
                        }
                        .padding(.leading, 8)
                        Spacer()
                    }
                }
                if lines.count > maxLines {
                    Text("… truncated at \(maxLines) lines …")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .padding(8)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Self.color(from: palette.background))
    }

    static func color(for kind: JSTokenKind, palette: ThemePalette) -> Color {
        color(from: palette.color(for: kind))
    }

    static func color(from palette: PaletteColor) -> Color {
        Color(red: palette.r, green: palette.g, blue: palette.b, opacity: palette.a)
    }
}
