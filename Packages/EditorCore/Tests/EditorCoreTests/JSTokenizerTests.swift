import XCTest
@testable import EditorCore

final class JSTokenizerTests: XCTestCase {

    private let tokenizer = JSTokenizer()

    private func kinds(in source: String) -> [(String, JSTokenKind)] {
        tokenizer.tokenize(source).map { (String(source[$0.range]), $0.kind) }
    }

    private func kind(at text: String, in source: String) -> JSTokenKind? {
        tokenizer.tokenize(source).first { String(source[$0.range]) == text }?.kind
    }

    func testKeywordsAndIdentifiers() {
        let tokens = kinds(in: "const value = data;")
        XCTAssertEqual(tokens.map(\.1), [.keyword, .identifier, .operator, .identifier, .punctuation])
        XCTAssertEqual(tokens[0].0, "const")
        XCTAssertEqual(tokens[1].0, "value")
    }

    func testLiterals() {
        XCTAssertEqual(kind(at: "true", in: "let a = true;"), .keyword)
        XCTAssertEqual(kind(at: "null", in: "let b = null;"), .keyword)
        XCTAssertEqual(kind(at: "undefined", in: "let c = undefined;"), .keyword)
    }

    func testNumberForms() {
        for literal in ["42", "3.14", "0x1F", "0b101", "0o17", "1e10", "2.5e-3", "1_000", "123n", ".5"] {
            let toks = tokenizer.tokenize("let n = \(literal);")
            XCTAssertTrue(toks.contains { $0.kind == .number && String("let n = \(literal);"[$0.range]) == literal },
                          "expected number token for \(literal)")
        }
    }

    func testStrings() {
        XCTAssertEqual(kind(at: "'hi'", in: "let s = 'hi';"), .string)
        XCTAssertEqual(kind(at: "\"hi\"", in: "let s = \"hi\";"), .string)
        XCTAssertEqual(kind(at: "'it\\'s'", in: "let s = 'it\\'s';"), .string)
    }

    func testLineAndBlockComments() {
        let toks = kinds(in: "let a = 1; // comment\nlet b = /* x */ 2;")
        let comments = toks.filter { $0.1 == .comment }
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].0, "// comment")
        XCTAssertEqual(comments[1].0, "/* x */")
    }

    func testRegexVsDivision() {
        // After `=` → regex
        let regex = tokenizer.tokenize("let r = /ab+c/g;")
        XCTAssertTrue(regex.contains { $0.kind == .regex && String("let r = /ab+c/g;"[$0.range]) == "/ab+c/g" })
        // After identifier → division
        let div = tokenizer.tokenize("let q = a / b;")
        XCTAssertTrue(div.contains { $0.kind == .operator && String("let q = a / b;"[$0.range]) == "/" })
        // After `)` → division
        let div2 = tokenizer.tokenize("x = (a+b) / c")
        XCTAssertTrue(div2.contains { $0.kind == .operator && String("x = (a+b) / c"[$0.range]) == "/" })
        // After `return` keyword → regex
        let re2 = tokenizer.tokenize("return /x/;")
        XCTAssertTrue(re2.contains { $0.kind == .regex })
        // Regex with character class containing slash
        let re3 = tokenizer.tokenize("let r = /[/]/;")
        XCTAssertTrue(re3.contains { $0.kind == .regex && String("let r = /[/]/;"[$0.range]) == "/[/]/" })
    }

    func testTemplateLiteralWithInterpolation() {
        let source = "let s = `hello ${name.toUpperCase()} and ${x + 1}`;"
        let toks = tokenizer.tokenize(source)
        // Interpolated identifiers tokenized as code, literal parts as templateString.
        XCTAssertTrue(toks.contains { $0.kind == .templateString })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "name" && $0.kind == .identifier })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "toUpperCase" && $0.kind == .property })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "x" && $0.kind == .identifier })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "1" && $0.kind == .number })
    }

    func testFunctionCallAndProperty() {
        let source = "console.log(greet('x')); obj.method();"
        let toks = tokenizer.tokenize(source)
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "console" && $0.kind == .builtin })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "log" && $0.kind == .property })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "greet" && $0.kind == .functionCall })
        XCTAssertTrue(toks.contains { String(source[$0.range]) == "method" && $0.kind == .property })
    }

    func testFullCoverage() {
        // Tokens are ordered, non-overlapping, and every non-whitespace character
        // belongs to some token (whitespace itself is skipped by design).
        let source = "const x = `a${1+2}b` === 'a3' ? /re/g : obj.m(); // done\n"
        let toks = tokenizer.tokenize(source)
        var covered = source.startIndex
        for tok in toks {
            let gap = source[covered..<tok.range.lowerBound]
            XCTAssertTrue(gap.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" },
                          "non-whitespace gap before token \(tok.range)")
            covered = tok.range.upperBound
        }
        XCTAssertTrue(source[covered...].allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
    }

    func testUnterminatedStringDoesNotHang() {
        let toks = tokenizer.tokenize("let s = 'oops\nlet t = 1;")
        XCTAssertFalse(toks.isEmpty)
    }
}
