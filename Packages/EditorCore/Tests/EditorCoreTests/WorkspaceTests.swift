import XCTest
@testable import EditorCore

final class WorkspaceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeIDETests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFileTreeLoad() throws {
        let sub = tempDir.appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "// a".write(to: tempDir.appendingPathComponent("a.js"), atomically: true, encoding: .utf8)
        try "// b".write(to: sub.appendingPathComponent("b.js"), atomically: true, encoding: .utf8)
        try ".hidden".write(to: tempDir.appendingPathComponent(".h.js"), atomically: true, encoding: .utf8)

        let tree = FileTree.load(root: tempDir)
        XCTAssertTrue(tree.isDirectory)
        let children = try XCTUnwrap(tree.children)
        XCTAssertEqual(children.count, 2) // hidden file skipped
        XCTAssertEqual(children[0].name, "lib") // directories sort first
        XCTAssertTrue(children[0].isDirectory)
        XCTAssertEqual(children[0].children?.first?.name, "b.js")
        XCTAssertEqual(children[1].name, "a.js")
    }

    func testCreateRenameDelete() throws {
        let url = try FileTree.createFile(named: "new.js", in: tempDir, contents: "let x = 1;")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Duplicate creation fails.
        XCTAssertThrowsError(try FileTree.createFile(named: "new.js", in: tempDir))

        let renamed = try FileTree.rename(url, to: "renamed.js")
        XCTAssertEqual(renamed.lastPathComponent, "renamed.js")

        try FileTree.delete(renamed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testDocumentLoadSave() throws {
        let url = tempDir.appendingPathComponent("doc.js")
        try "console.log(1);".write(to: url, atomically: true, encoding: .utf8)

        var doc = try ScriptDocument.load(from: url)
        XCTAssertEqual(doc.displayName, "doc.js")
        XCTAssertEqual(doc.text, "console.log(1);")
        XCTAssertFalse(doc.isDirty)

        doc.text = "console.log(2);"
        doc.isDirty = true
        try doc.save()
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "console.log(2);")
    }

    func testUntitledDocumentSaveAs() throws {
        var doc = ScriptDocument(displayName: "Untitled", text: "print(1);")
        XCTAssertNil(doc.fileURL)
        XCTAssertThrowsError(try doc.save())
        let url = tempDir.appendingPathComponent("scratch.js")
        try doc.save(to: url)
        XCTAssertEqual(doc.fileURL, url)
        XCTAssertEqual(doc.displayName, "scratch.js")
    }

    func testEditableExtensions() {
        XCTAssertTrue(FileTree.isEditable(URL(fileURLWithPath: "/x/main.js")))
        XCTAssertTrue(FileTree.isEditable(URL(fileURLWithPath: "/x/data.JSON")))
        XCTAssertFalse(FileTree.isEditable(URL(fileURLWithPath: "/x/image.png")))
    }
}
