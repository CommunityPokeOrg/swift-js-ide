import Foundation

/// A node in the project file tree shown in the sidebar.
public struct FileNode: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var children: [FileNode]?

    public init(url: URL, name: String, isDirectory: Bool, children: [FileNode]? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }
}

/// Loads and mutates an on-disk directory tree for the sidebar.
public enum FileTree {

    /// Extensions treated as editable source files.
    public static let editableExtensions: Set<String> = [
        "js", "mjs", "cjs", "jsx", "ts", "json", "txt", "md", "html", "css"
    ]

    /// Recursively scans `root` into a sorted tree (directories first, then files,
    /// alphabetical). Hidden files are skipped.
    public static func load(root url: URL, maxDepth: Int = 12) -> FileNode {
        func node(at url: URL, depth: Int) -> FileNode {
            let name = url.lastPathComponent
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue, depth < maxDepth else {
                return FileNode(url: url, name: name, isDirectory: false)
            }
            let childURLs = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let children = childURLs.map { node(at: $0, depth: depth + 1) }.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return FileNode(url: url, name: name, isDirectory: true, children: children)
        }
        return node(at: url, depth: 0)
    }

    public static func createFile(named name: String, in directory: URL, contents: String = "") throws -> URL {
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func rename(_ url: URL, to newName: String) throws -> URL {
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    public static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// Whether a file URL looks like something the editor can open as text.
    public static func isEditable(_ url: URL) -> Bool {
        editableExtensions.contains(url.pathExtension.lowercased())
    }
}

/// An editable JavaScript (or other text) document.
public struct ScriptDocument: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var text: String
    /// Backing file URL; `nil` for untitled scratch documents.
    public var fileURL: URL?
    public var isDirty: Bool

    public init(id: UUID = UUID(), displayName: String, text: String,
                fileURL: URL? = nil, isDirty: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.text = text
        self.fileURL = fileURL
        self.isDirty = isDirty
    }

    public static func load(from url: URL) throws -> ScriptDocument {
        let text = try String(contentsOf: url, encoding: .utf8)
        return ScriptDocument(displayName: url.lastPathComponent, text: text, fileURL: url)
    }

    /// Writes the document back to its `fileURL`, or to `url` when provided (Save As / export).
    @discardableResult
    public mutating func save(to url: URL? = nil) throws -> URL {
        let target = url ?? fileURL
        guard let target else {
            throw CocoaError(.fileNoSuchFile)
        }
        try text.write(to: target, atomically: true, encoding: .utf8)
        fileURL = target
        displayName = target.lastPathComponent
        isDirty = false
        return target
    }
}
