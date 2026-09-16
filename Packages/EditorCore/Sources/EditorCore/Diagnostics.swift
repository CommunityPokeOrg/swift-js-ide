import Foundation

public enum DiagnosticSeverity: String, Sendable, CaseIterable {
    case error
    case warning
}

/// A problem found in a JavaScript source — syntax error, runtime exception, or lint warning.
public struct JSDiagnostic: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String
    /// 1-based line number, when the engine reported one.
    public let line: Int?
    /// 1-based column number, when the engine reported one.
    public let column: Int?
    public let severity: DiagnosticSeverity
    /// Name of the script/document the diagnostic belongs to, when known.
    public let sourceName: String?

    public init(id: UUID = UUID(), message: String, line: Int? = nil, column: Int? = nil,
                severity: DiagnosticSeverity = .error, sourceName: String? = nil) {
        self.id = id
        self.message = message
        self.line = line
        self.column = column
        self.severity = severity
        self.sourceName = sourceName
    }

    public var locationDescription: String {
        switch (line, column) {
        case let (l?, c?): return "line \(l), column \(c)"
        case let (l?, nil): return "line \(l)"
        default: return ""
        }
    }
}
