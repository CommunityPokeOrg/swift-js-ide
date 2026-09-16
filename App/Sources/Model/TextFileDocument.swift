import SwiftUI
import UniformTypeIdentifiers

/// Minimal `FileDocument` wrapper used only for `.fileExporter` — the exporter
/// API requires a document type even when exporting raw text.
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.javaScript, .plainText] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
