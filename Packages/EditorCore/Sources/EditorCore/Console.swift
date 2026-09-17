import Foundation

/// Severity of a console output line produced by running JavaScript.
public enum ConsoleLevel: String, Sendable, CaseIterable {
    case log
    case info
    case debug
    case warn
    case error
    /// The completion value of a top-level `evaluate` call.
    case result
    /// IDE-generated messages (run started/stopped, engine unavailable…).
    case system
}

/// One line in the output console.
public struct ConsoleEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let level: ConsoleLevel
    public let message: String
    public let timestamp: Date

    public init(id: UUID = UUID(), level: ConsoleLevel, message: String, timestamp: Date = Date()) {
        self.id = id
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}
