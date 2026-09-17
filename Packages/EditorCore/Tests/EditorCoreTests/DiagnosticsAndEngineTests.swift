import XCTest
@testable import EditorCore

final class DiagnosticsTests: XCTestCase {

    func testLocationDescription() {
        XCTAssertEqual(JSDiagnostic(message: "m", line: 3, column: 7).locationDescription, "line 3, column 7")
        XCTAssertEqual(JSDiagnostic(message: "m", line: 3).locationDescription, "line 3")
        XCTAssertEqual(JSDiagnostic(message: "m").locationDescription, "")
    }

    func testConsoleEntry() {
        let entry = ConsoleEntry(level: .warn, message: "careful")
        XCTAssertEqual(entry.level, .warn)
        XCTAssertEqual(entry.message, "careful")
    }
}

final class JSEngineTests: XCTestCase {

    func testUnavailableEngineReportsSystemEntry() {
        let engine = UnavailableEngine()
        var entries: [ConsoleEntry] = []
        var finished = false
        engine.onConsoleEntry = { entries.append($0) }
        engine.onFinish = { finished = true }
        engine.evaluate("1+1", named: "test.js")
        XCTAssertTrue(finished)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.level, .system)
        XCTAssertNil(engine.checkSyntax("(", named: "x.js"))
    }

    #if canImport(JavaScriptCore)
    func testJavaScriptCoreEvaluation() {
        let engine = JavaScriptCoreEngine()
        var entries: [ConsoleEntry] = []
        var finished = XCTestExpectation(description: "run finished")
        engine.onConsoleEntry = { entries.append($0) }
        engine.onFinish = { finished.fulfill() }

        engine.evaluate("""
        console.log('hello');
        console.warn(1 + 2);
        print('direct');
        21 * 2;
        """, named: "test.js")

        wait(for: [finished], timeout: 10)
        let messages = entries.map(\.message)
        XCTAssertTrue(messages.contains("hello"))
        XCTAssertTrue(entries.contains { $0.level == .warn && $0.message == "3" })
        XCTAssertTrue(messages.contains("direct"))
        XCTAssertTrue(entries.contains { $0.level == .result && $0.message.contains("42") })
    }

    func testJavaScriptCoreExceptionDiagnostic() {
        let engine = JavaScriptCoreEngine()
        var diags: [JSDiagnostic] = []
        var finished = XCTestExpectation(description: "run finished")
        engine.onDiagnostics = { diags.append(contentsOf: $0) }
        engine.onFinish = { finished.fulfill() }

        engine.evaluate("throw new Error('boom');", named: "bad.js")
        wait(for: [finished], timeout: 10)
        XCTAssertFalse(diags.isEmpty)
        XCTAssertTrue(diags.first?.message.contains("boom") ?? false)
    }

    func testCheckSyntax() {
        let engine = JavaScriptCoreEngine()
        XCTAssertNil(engine.checkSyntax("let x = 1 + 2;", named: "ok.js"))
        XCTAssertNotNil(engine.checkSyntax("let x = ;", named: "bad.js"))
    }
    #endif
}
