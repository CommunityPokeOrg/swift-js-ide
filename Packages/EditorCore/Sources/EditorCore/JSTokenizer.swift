import Foundation

/// Semantic category for a lexed JavaScript token, used to drive syntax highlighting.
public enum JSTokenKind: String, Sendable, CaseIterable {
    case keyword
    case builtin
    case number
    case string
    case templateString
    case regex
    case comment
    case `operator`
    case punctuation
    case identifier
    case property
    case functionCall
}

/// A single lexed token: a kind plus a half-open range into the source string.
public struct JSToken: Equatable, Sendable {
    public let kind: JSTokenKind
    public let range: Range<String.Index>

    public init(kind: JSTokenKind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}

/// A hand-written lexer for JavaScript/ECMAScript source text.
///
/// Produces `[JSToken]` covering the entire input (whitespace is skipped, not emitted).
/// Handles line/block comments, single/double-quoted strings, template literals with
/// nested `${ ... }` interpolation, regular expressions (via a heuristic that decides
/// between `/` as regex vs division), all numeric literal forms, and operator/punctuation
/// longest-match splitting.
public struct JSTokenizer: Sendable {

    public static let keywords: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "default", "delete", "do", "else", "enum", "export", "extends", "finally",
        "for", "function", "get", "if", "implements", "import", "in", "instanceof",
        "interface", "let", "new", "of", "package", "private", "protected", "public",
        "return", "set", "static", "super", "switch", "this", "throw", "try",
        "typeof", "var", "void", "while", "with", "yield",
        "true", "false", "null", "undefined", "async"
    ]

    /// Keywords that act as operands — a `/` after these is division, not a regex.
    private static let operandKeywords: Set<String> = [
        "this", "super", "true", "false", "null", "undefined"
    ]

    /// Well-known global identifiers highlighted distinctly.
    public static let builtins: Set<String> = [
        "AggregateError", "Array", "ArrayBuffer", "AsyncFunction", "Atomics", "BigInt",
        "BigInt64Array", "BigUint64Array", "Boolean", "DataView", "Date", "Error",
        "EvalError", "FinalizationRegistry", "Float32Array", "Float64Array",
        "Function", "Generator", "GeneratorFunction", "Infinity", "Int8Array",
        "Int16Array", "Int32Array", "Intl", "JSON", "Map", "Math", "NaN", "Number",
        "Object", "Promise", "Proxy", "RangeError", "ReferenceError", "Reflect",
        "RegExp", "Set", "SharedArrayBuffer", "String", "Symbol", "SyntaxError",
        "TypeError", "Uint8Array", "Uint8ClampedArray", "Uint16Array", "Uint32Array",
        "URIError", "WeakMap", "WeakRef", "WeakSet",
        "clearInterval", "clearTimeout", "console", "decodeURI",
        "decodeURIComponent", "encodeURI", "encodeURIComponent", "eval", "fetch",
        "globalThis", "isFinite", "isNaN", "module", "parseFloat", "parseInt",
        "print", "process", "queueMicrotask", "require", "setInterval", "setTimeout",
        "structuredClone", "undefined", "window", "document", "exports", "crypto"
    ]

    /// Multi-char operators, ordered longest-first for greedy matching.
    private static let operators: [String] = [
        ">>>=", "===", "!==", "**=", "<<=", ">>=", "??=", "...", "&&=", "||=",
        ">>>", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "++", "--",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "**", "?.",
        "&", "|", "^", "~", "!", "<", ">", "+", "-", "*", "/", "%", "=", "?", ":"
    ]

    private static let punctuation: Set<Character> = ["(", ")", "[", "]", "{", "}", ";", ",", ".", "@"]

    public init() {}

    /// Lexes `source` into semantic tokens. Never fails; malformed input is emitted
    /// as the closest reasonable token kind.
    public func tokenize(_ source: String) -> [JSToken] {
        var lexer = Cursor(source: source)
        var tokens: [JSToken] = []
        // Significant-token context used for the regex-vs-division heuristic and
        // property classification after `.`.
        var prevKind: JSTokenKind? = nil
        var prevWasDot = false
        var prevWasOperandKeyword = false
        // The most recently emitted punctuation character, if any — `)`/`]`/`}`
        // end expressions, so a following `/` is division rather than a regex.
        var prevPunctuation: Character? = nil
        // Stack of brace-depths for `${ }` template interpolation. When we open a
        // `${`, we push the current brace depth; when a `}` would drop below the top
        // of the stack we know the interpolation ended.
        var interpolationStack: [Int] = []
        var braceDepth = 0

        while !lexer.isAtEnd {
            guard let c = lexer.peek() else { break }

            // Whitespace: skip without emitting.
            if c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0B}" || c == "\u{0C}" {
                lexer.advance()
                continue
            }

            let start = lexer.index

            // Comments
            if c == "/" && lexer.peekNext() == "/" {
                while let ch = lexer.peek(), ch != "\n" { lexer.advance() }
                tokens.append(JSToken(kind: .comment, range: start..<lexer.index))
                continue
            }
            if c == "/" && lexer.peekNext() == "*" {
                lexer.advance(); lexer.advance()
                while !lexer.isAtEnd {
                    if lexer.peek() == "*" && lexer.peekNext() == "/" {
                        lexer.advance(); lexer.advance()
                        break
                    }
                    lexer.advance()
                }
                tokens.append(JSToken(kind: .comment, range: start..<lexer.index))
                continue
            }

            // Strings
            if c == "\"" || c == "'" {
                lexer.advance()
                while let ch = lexer.peek() {
                    if ch == "\\" { lexer.advance(); lexer.advance(); continue }
                    if ch == c { lexer.advance(); break }
                    if ch == "\n" { break } // unterminated: end token at newline
                    lexer.advance()
                }
                tokens.append(JSToken(kind: .string, range: start..<lexer.index))
                setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .string)
                continue
            }

            // Template literal
            if c == "`" {
                lexer.advance()
                var emittedEnd = false
                while let ch = lexer.peek() {
                    if ch == "\\" { lexer.advance(); lexer.advance(); continue }
                    if ch == "`" { lexer.advance(); emittedEnd = true; break }
                    if ch == "$" && lexer.peekNext() == "{" {
                        // Emit the literal portion, then a punctuation token for `${`.
                        tokens.append(JSToken(kind: .templateString, range: start..<lexer.index))
                        lexer.advance(); lexer.advance()
                        tokens.append(JSToken(kind: .punctuation, range: lexer.index(before: lexer.index, offsetBy: 2)..<lexer.index))
                        interpolationStack.append(braceDepth)
                        braceDepth += 1
                        emittedEnd = false
                        break
                    }
                    lexer.advance()
                }
                if emittedEnd || lexer.isAtEnd {
                    if !emittedEnd || tokens.last?.kind != .templateString {
                        tokens.append(JSToken(kind: .templateString, range: start..<lexer.index))
                    }
                    setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .templateString)
                } else {
                    // Dropped into interpolation: code resumes with template state pushed.
                    prevKind = nil; prevWasDot = false; prevWasOperandKeyword = false
                }
                continue
            }

            // Regex literal vs division
            if c == "/" && regexAllowed(prevKind: prevKind, prevWasOperandKeyword: prevWasOperandKeyword,
                                        prevPunctuation: prevPunctuation) {
                lexer.advance()
                var inClass = false
                var closed = false
                while let ch = lexer.peek() {
                    if ch == "\\" { lexer.advance(); lexer.advance(); continue }
                    if ch == "\n" { break }
                    if ch == "[" { inClass = true }
                    else if ch == "]" { inClass = false }
                    else if ch == "/" && !inClass { lexer.advance(); closed = true; break }
                    lexer.advance()
                }
                if closed {
                    while let ch = lexer.peek(), ch.isLetter { lexer.advance() } // flags
                }
                tokens.append(JSToken(kind: closed ? .regex : .operator, range: start..<lexer.index))
                setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, closed ? .regex : .operator)
                continue
            }

            // Numbers
            if c.isNumber || (c == "." && lexer.peekNext()?.isNumber == true) {
                lexNumber(&lexer)
                tokens.append(JSToken(kind: .number, range: start..<lexer.index))
                setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .number)
                continue
            }

            // Identifiers / keywords
            if c == "_" || c == "$" || c.isLetter {
                while let ch = lexer.peek(), ch == "_" || ch == "$" || ch.isLetter || ch.isNumber {
                    lexer.advance()
                }
                let word = String(source[start..<lexer.index])
                if Self.keywords.contains(word) {
                    tokens.append(JSToken(kind: .keyword, range: start..<lexer.index))
                    prevKind = .keyword
                    prevWasDot = false
                    prevWasOperandKeyword = Self.operandKeywords.contains(word)
                } else if Self.builtins.contains(word) {
                    tokens.append(JSToken(kind: .builtin, range: start..<lexer.index))
                    setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .builtin)
                } else if prevWasDot {
                    tokens.append(JSToken(kind: .property, range: start..<lexer.index))
                    setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .property)
                } else if lexer.nextNonWhitespaceIsOpenParen {
                    tokens.append(JSToken(kind: .functionCall, range: start..<lexer.index))
                    setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .functionCall)
                } else {
                    tokens.append(JSToken(kind: .identifier, range: start..<lexer.index))
                    setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .identifier)
                }
                continue
            }

            // Operators (greedy longest match) — must run before punctuation so
            // `...` and `?.` win over `.`.
            if let op = Self.operators.first(where: { lexer.hasPrefix($0) }) {
                for _ in op { lexer.advance() }
                tokens.append(JSToken(kind: .operator, range: start..<lexer.index))
                setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .operator)
                continue
            }

            // Punctuation
            if Self.punctuation.contains(c) {
                lexer.advance()
                tokens.append(JSToken(kind: .punctuation, range: start..<lexer.index))
                prevKind = .punctuation
                prevPunctuation = c
                if c == "." { prevWasDot = true } else { prevWasDot = false }
                if c == "{" { braceDepth += 1 }
                if c == "}" {
                    braceDepth = max(0, braceDepth - 1)
                    if let interp = interpolationStack.last, braceDepth <= interp {
                        interpolationStack.removeLast()
                        // Resume template literal mode: lex until ` or ${ again.
                        let tstart = lexer.index
                        var closed = false
                        while let ch = lexer.peek() {
                            if ch == "\\" { lexer.advance(); lexer.advance(); continue }
                            if ch == "`" { closed = true; break }
                            if ch == "$" && lexer.peekNext() == "{" { break }
                            lexer.advance()
                        }
                        if closed { lexer.advance() } // include the closing backtick
                        if tstart != lexer.index {
                            tokens.append(JSToken(kind: .templateString, range: tstart..<lexer.index))
                        }
                        else if lexer.peek() == "$" && lexer.peekNext() == "{" {
                            lexer.advance(); lexer.advance()
                            tokens.append(JSToken(kind: .punctuation, range: lexer.index(before: lexer.index, offsetBy: 2)..<lexer.index))
                            interpolationStack.append(braceDepth)
                            braceDepth += 1
                        }
                        setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .templateString)
                        continue
                    }
                }
                prevWasOperandKeyword = false
                continue
            }

            // Unknown character: emit as identifier to keep coverage contiguous.
            lexer.advance()
            tokens.append(JSToken(kind: .identifier, range: start..<lexer.index))
            setPrev(&prevKind, &prevWasDot, &prevWasOperandKeyword, &prevPunctuation, .identifier)
        }

        return tokens
    }

    private func setPrev(_ kind: inout JSTokenKind?, _ dot: inout Bool, _ operandKw: inout Bool,
                         _ punct: inout Character?, _ new: JSTokenKind) {
        kind = new
        dot = false
        operandKw = false
        punct = nil
    }

    /// `/` starts a regex when the previous significant token can't end an expression.
    private func regexAllowed(prevKind: JSTokenKind?, prevWasOperandKeyword: Bool,
                              prevPunctuation: Character?) -> Bool {
        guard let prev = prevKind else { return true }
        switch prev {
        case .operator:
            return true
        case .punctuation:
            guard let c = prevPunctuation else { return true }
            return c != ")" && c != "]" && c != "}"
        case .keyword:
            return !prevWasOperandKeyword
        case .comment:
            return true
        case .identifier, .number, .string, .templateString, .regex, .builtin, .property, .functionCall:
            return false
        }
    }

    private func lexNumber(_ lexer: inout Cursor) {
        guard let first = lexer.peek() else { return }
        if first == "0", let next = lexer.peekNext() {
            switch next {
            case "x", "X": lexer.advance(); lexer.advance(); consumeWhile(&lexer) { $0.isHexDigit || $0 == "_" }; consumeBigIntSuffix(&lexer); return
            case "o", "O": lexer.advance(); lexer.advance(); consumeWhile(&lexer) { ("0"..."7").contains($0) || $0 == "_" }; consumeBigIntSuffix(&lexer); return
            case "b", "B": lexer.advance(); lexer.advance(); consumeWhile(&lexer) { $0 == "0" || $0 == "1" || $0 == "_" }; consumeBigIntSuffix(&lexer); return
            default: break
            }
        }
        consumeWhile(&lexer) { $0.isNumber || $0 == "_" }
        if lexer.peek() == "." { lexer.advance(); consumeWhile(&lexer) { $0.isNumber || $0 == "_" } }
        if let e = lexer.peek(), e == "e" || e == "E" {
            lexer.advance()
            if let s = lexer.peek(), s == "+" || s == "-" { lexer.advance() }
            consumeWhile(&lexer) { $0.isNumber || $0 == "_" }
        }
        consumeBigIntSuffix(&lexer)
    }

    private func consumeWhile(_ lexer: inout Cursor, _ pred: (Character) -> Bool) {
        while let ch = lexer.peek(), pred(ch) { lexer.advance() }
    }

    private func consumeBigIntSuffix(_ lexer: inout Cursor) {
        if lexer.peek() == "n" { lexer.advance() }
    }

    /// Minimal source cursor over a String's indices.
    private struct Cursor {
        let source: String
        var index: String.Index

        init(source: String) {
            self.source = source
            self.index = source.startIndex
        }

        var isAtEnd: Bool { index >= source.endIndex }

        func peek() -> Character? {
            isAtEnd ? nil : source[index]
        }

        func peekNext() -> Character? {
            guard !isAtEnd else { return nil }
            let next = source.index(after: index)
            return next < source.endIndex ? source[next] : nil
        }

        mutating func advance() {
            if !isAtEnd { source.formIndex(after: &index) }
        }

        func hasPrefix(_ s: String) -> Bool {
            var i = index
            for ch in s {
                guard i < source.endIndex, source[i] == ch else { return false }
                source.formIndex(after: &i)
            }
            return true
        }

        func index(before i: String.Index, offsetBy n: Int) -> String.Index {
            source.index(i, offsetBy: -n)
        }

        /// True when the next non-whitespace character is `(`.
        var nextNonWhitespaceIsOpenParen: Bool {
            var i = index
            while i < source.endIndex {
                let ch = source[i]
                if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
                    source.formIndex(after: &i)
                    continue
                }
                return ch == "("
            }
            return false
        }
    }
}
