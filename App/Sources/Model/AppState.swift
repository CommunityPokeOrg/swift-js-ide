import Foundation
import EditorCore
import Combine

/// A request for the editor to scroll a line into view (e.g. from a diagnostic tap).
public struct RevealRequest: Equatable {
    public let id = UUID()
    public let line: Int
    public init(line: Int) { self.line = line }
}

public enum RunState: Equatable {
    case idle
    case running
}

/// Central observable state for the IDE: workspace tree, open documents, console,
/// diagnostics and the evaluation engine. Single source of truth shared by the
/// SwiftUI scene and the command menus.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Workspace

    @Published public private(set) var rootNode: FileNode?
    @Published public private(set) var rootURL: URL?
    /// Security-scoped URLs kept accessible for the lifetime of the session.
    private var accessedURLs: [URL] = []

    // MARK: - Documents

    @Published public var documents: [ScriptDocument] = []
    @Published public var selectedDocumentID: UUID?
    /// Line the editor should scroll to (diagnostic navigation).
    @Published public var revealRequest: RevealRequest?

    // MARK: - Console & diagnostics

    @Published public private(set) var consoleEntries: [ConsoleEntry] = []
    @Published public private(set) var diagnostics: [JSDiagnostic] = []
    private let consoleLimit = 2_000

    // MARK: - Run state

    @Published public private(set) var runState: RunState = .idle
    private var engine: JSEvaluating?
    private let lintEngine: JSEvaluating = JSEngineFactory.makeEngine()
    private var lintTask: Task<Void, Never>?

    // MARK: - Presentation

    @Published public var isFolderPickerPresented = false
    @Published public var isImporterPresented = false
    @Published public var isExporterPresented = false
    @Published public var isNewFileAlertPresented = false
    @Published public var newFileName = "untitled.js"
    @Published public var errorMessage: String?

    public var selectedDocument: ScriptDocument? {
        documents.first { $0.id == selectedDocumentID }
    }

    public init() {}

    // MARK: - Documents

    public func newDocument() {
        let number = documents.filter { $0.displayName.hasPrefix("untitled") }.count + 1
        var doc = ScriptDocument(
            displayName: "untitled\(number > 1 ? "-\(number)" : "").js",
            text: "// New script\nconsole.log('Hello from PokeIDE!');\n"
        )
        doc.isDirty = true
        documents.append(doc)
        selectedDocumentID = doc.id
    }

    public func openFile(at url: URL) {
        guard FileTree.isEditable(url) else {
            errorMessage = "\(url.lastPathComponent) is not a supported text file."
            return
        }
        if let existing = documents.first(where: { $0.fileURL == url }) {
            selectedDocumentID = existing.id
            return
        }
        do {
            let doc = try ScriptDocument.load(from: url)
            documents.append(doc)
            selectedDocumentID = doc.id
        } catch {
            errorMessage = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    public func select(_ doc: ScriptDocument) {
        selectedDocumentID = doc.id
    }

    public func close(_ doc: ScriptDocument) {
        documents.removeAll { $0.id == doc.id }
        if selectedDocumentID == doc.id {
            selectedDocumentID = documents.last?.id
        }
    }

    public func closeSelected() {
        if let doc = selectedDocument { close(doc) }
    }

    public func updateText(_ text: String, for docID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == docID }) else { return }
        documents[index].text = text
        documents[index].isDirty = true
        scheduleSyntaxCheck(for: documents[index])
    }

    public func saveCurrent() {
        guard var doc = selectedDocument else { return }
        guard doc.fileURL != nil else {
            // Untitled documents go through the exporter (Save As).
            isExporterPresented = true
            return
        }
        do {
            try doc.save()
            if let index = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[index] = doc
            }
        } catch {
            errorMessage = "Couldn't save \(doc.displayName): \(error.localizedDescription)"
        }
    }

    public func exportCurrent(to url: URL) {
        guard var doc = selectedDocument else { return }
        do {
            try doc.save(to: url)
            if let index = documents.firstIndex(where: { $0.id == doc.id }) {
                documents[index] = doc
            }
        } catch {
            errorMessage = "Couldn't export \(doc.displayName): \(error.localizedDescription)"
        }
    }

    // MARK: - Workspace

    public func openFolder(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }
        saveBookmark(for: url)
        rootURL = url
        rootNode = FileTree.load(root: url)
        openFirstEditableFile()
    }

    public func refreshWorkspace() {
        guard let rootURL else { return }
        rootNode = FileTree.load(root: rootURL)
    }

    public func importFiles(_ urls: [URL]) {
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
            openFile(at: url)
        }
    }

    public func createFileInWorkspace(named name: String) {
        guard let rootURL else { return }
        let fileName = name.isEmpty ? "untitled.js" : name
        do {
            let url = try FileTree.createFile(named: fileName, in: rootURL)
            refreshWorkspace()
            openFile(at: url)
        } catch {
            errorMessage = "Couldn't create \(fileName): \(error.localizedDescription)"
        }
    }

    public func delete(node: FileNode) {
        do {
            try FileTree.delete(node.url)
            if let doc = documents.first(where: { $0.fileURL == node.url }) {
                close(doc)
            }
            refreshWorkspace()
        } catch {
            errorMessage = "Couldn't delete \(node.name): \(error.localizedDescription)"
        }
    }

    public func rename(node: FileNode, to newName: String) {
        do {
            let newURL = try FileTree.rename(node.url, to: newName)
            if let index = documents.firstIndex(where: { $0.fileURL == node.url }) {
                documents[index].fileURL = newURL
                documents[index].displayName = newURL.lastPathComponent
            }
            refreshWorkspace()
        } catch {
            errorMessage = "Couldn't rename \(node.name): \(error.localizedDescription)"
        }
    }

    private func openFirstEditableFile() {
        guard let node = rootNode else { return }
        func firstFile(_ node: FileNode) -> FileNode? {
            if !node.isDirectory { return FileTree.isEditable(node.url) ? node : nil }
            for child in node.children ?? [] {
                if let found = firstFile(child) { return found }
            }
            return nil
        }
        if let file = firstFile(node) {
            openFile(at: file.url)
        }
    }

    // MARK: - Bookmarks (reopen last workspace across launches)

    private static let bookmarkKey = "LastWorkspaceBookmark"

    private func saveBookmark(for url: URL) {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        if let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    public func restoreLastWorkspace() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        guard let url = try? URL(resolvingBookmarkData: data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale), !stale else { return }
        openFolder(url)
    }

    // MARK: - Running

    public func run() {
        guard let doc = selectedDocument else { return }
        stop()
        let engine = JSEngineFactory.makeEngine()
        self.engine = engine
        runState = .running
        append(.system, "Running \(doc.displayName)…")

        engine.onConsoleEntry = { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
        engine.onDiagnostics = { [weak self] diags in
            Task { @MainActor in
                guard let self else { return }
                self.diagnostics = diags
                for diag in diags {
                    self.append(.error, "\(diag.message) \(diag.locationDescription)")
                }
            }
        }
        engine.onFinish = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.runState = .idle
                self.append(.system, "Finished.")
            }
        }
        engine.evaluate(doc.text, named: doc.displayName)
    }

    public func stop() {
        guard runState == .running, let engine else { return }
        engine.requestStop()
    }

    public func clearConsole() {
        consoleEntries.removeAll()
    }

    private func append(_ level: ConsoleLevel, _ message: String) {
        append(ConsoleEntry(level: level, message: message))
    }

    private func append(_ entry: ConsoleEntry) {
        consoleEntries.append(entry)
        if consoleEntries.count > consoleLimit {
            consoleEntries.removeFirst(consoleEntries.count - consoleLimit)
        }
    }

    // MARK: - Diagnostics

    /// Debounced syntax check (parse only — no execution) used for the Problems list.
    private func scheduleSyntaxCheck(for doc: ScriptDocument) {
        lintTask?.cancel()
        let source = doc.text
        let name = doc.displayName
        lintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let diagnostic = await Task.detached(priority: .userInitiated) {
                self?.lintEngine.checkSyntax(source, named: name)
            }.value
            guard !Task.isCancelled, let self else { return }
            if let diagnostic {
                self.diagnostics = [diagnostic]
            } else if self.runState != .running {
                self.diagnostics = []
            }
        }
    }

    public func reveal(_ diagnostic: JSDiagnostic) {
        if let name = diagnostic.sourceName,
           let doc = documents.first(where: { $0.displayName == name }) {
            selectedDocumentID = doc.id
        }
        if let line = diagnostic.line {
            revealRequest = RevealRequest(line: line)
        }
    }

    // MARK: - Demo / CI hooks

    /// Loads the bundled demo script when launched with `POKEIDE_DEMO=1`
    /// (used by CI to capture screenshots of a running session).
    public func loadDemoIfRequested() {
        guard ProcessInfo.processInfo.environment["POKEIDE_DEMO"] == "1",
              documents.isEmpty else { return }
        if let url = Bundle.main.url(forResource: "demo", withExtension: "js"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            var doc = ScriptDocument(displayName: "demo.js", text: text, fileURL: nil)
            doc.isDirty = false
            documents = [doc]
            selectedDocumentID = doc.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.run()
            }
        } else {
            newDocument()
        }
    }
}
