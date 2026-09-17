import Foundation
import EditorCore

/// Linux implementation of `JSEvaluating` backed by a `node` subprocess.
///
/// JavaScriptCore is an Apple framework, so on Linux the IDE executes scripts
/// by writing them to a temp file and running `node <file>` — real execution
/// with real `console.*` output. stdout lines map to `.log`, stderr to `.error`,
/// and non-zero exits get parsed into `JSDiagnostic`s from node's
/// `file:line` error prefix.
///
/// `requestStop` sends SIGTERM — unlike JavaScriptCore, a runaway
/// `while (true)` can actually be killed here.
public final class NodeEngine: JSEvaluating {
    private let queue = DispatchQueue(label: "org.communitypoke.pokeide.node-engine", qos: .userInitiated)
    private var generation = 0
    private var cancelled = false
    private var process: Process?

    public private(set) var isRunning = false
    public var onConsoleEntry: ((ConsoleEntry) -> Void)?
    public var onDiagnostics: (([JSDiagnostic]) -> Void)?
    public var onFinish: (() -> Void)?

    public init() {}

    public static func isNodeAvailable() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["node", "--version"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return (try? p.run()) != nil
    }

    public func evaluate(_ source: String, named name: String) {
        queue.async { [self] in
            generation += 1
            let gen = generation
            cancelled = false
            isRunning = true
            emit(.system, "Running \(name)…")

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("pokeide-\(UUID().uuidString.prefix(8)).js")
            do {
                try source.write(to: tmp, atomically: true, encoding: .utf8)
            } catch {
                emit(.error, "Couldn't write temp script: \(error.localizedDescription)")
                finish()
                return
            }
            defer { try? FileManager.default.removeItem(at: tmp) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["node", tmp.path]
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            do {
                try process.run()
            } catch {
                emit(.error, "Couldn't start node: \(error.localizedDescription)")
                finish()
                return
            }
            self.process = process

            // Drain both pipes concurrently so large outputs can't deadlock on a
            // full pipe buffer while the process is still running.
            let group = DispatchGroup()
            let captured = OutputCapture()
            group.enter()
            DispatchQueue.global().async {
                captured.stdoutData = out.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            DispatchQueue.global().async {
                captured.stderrData = err.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }

            process.waitUntilExit()
            group.wait()
            self.process = nil

            guard generation == gen else { return }

            let stdout = String(data: captured.stdoutData, encoding: .utf8) ?? ""
            for line in stdout.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
                guard !cancelled else { break }
                emit(.log, String(line))
            }

            let stderr = String(data: captured.stderrData, encoding: .utf8) ?? ""
            if !stderr.isEmpty {
                for line in stderr.split(separator: "\n") {
                    emit(process.terminationStatus == 0 ? .warn : .error, String(line))
                }
                let diags = Self.parseDiagnostics(stderr: stderr, sourceName: name, scriptPath: tmp.path)
                if !diags.isEmpty, !cancelled {
                    onDiagnostics?(diags)
                }
            }

            if process.terminationStatus == 0 {
                emit(.system, "Finished (exit 0).")
            } else {
                emit(.system, "Exited with status \(process.terminationStatus).")
            }
            finish()
        }
    }

    public func requestStop() {
        queue.async { [self] in
            cancelled = true
            process?.terminate() // SIGTERM — actually kills runaway scripts
            if isRunning { emit(.system, "Stopped.") }
            finish()
        }
    }

    /// `node --check` — parses without executing.
    public func checkSyntax(_ source: String, named name: String) -> JSDiagnostic? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokeide-check-\(UUID().uuidString.prefix(8)).js")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let _ = try? source.write(to: tmp, atomically: true, encoding: .utf8) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "--check", tmp.path]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = FileHandle.nullDevice
        guard let _ = try? process.run() else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Self.parseDiagnostics(stderr: stderr, sourceName: name, scriptPath: tmp.path).first
            ?? JSDiagnostic(message: "Syntax error", sourceName: name)
    }

    /// Synchronous one-shot execution used to seed the console at startup.
    public static func runSync(_ source: String) -> [ConsoleEntry] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pokeide-seed-\(UUID().uuidString.prefix(8)).js")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard let _ = try? source.write(to: tmp, atomically: true, encoding: .utf8) else {
            return [ConsoleEntry(level: .error, message: "Couldn't write temp file")]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", tmp.path]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        guard (try? process.run()) != nil else {
            return [ConsoleEntry(level: .system, message: "node not found on PATH")]
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var entries = [ConsoleEntry(level: .system, message: "Running demo.js…")]
        for line in (String(data: outData, encoding: .utf8) ?? "").split(separator: "\n") {
            entries.append(ConsoleEntry(level: .log, message: String(line)))
        }
        for line in (String(data: errData, encoding: .utf8) ?? "").split(separator: "\n") {
            entries.append(ConsoleEntry(level: .error, message: String(line)))
        }
        entries.append(ConsoleEntry(level: .system,
                                    message: "Finished (exit \(process.terminationStatus))."))
        return entries
    }

    /// Parses node's `path:LINE` error prefix into diagnostics.
    static func parseDiagnostics(stderr: String, sourceName: String, scriptPath: String) -> [JSDiagnostic] {
        var diags: [JSDiagnostic] = []
        var pendingLine: Int? = nil
        for line in stderr.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix(scriptPath + ":") || s.hasPrefix("file://\(scriptPath):") {
                pendingLine = Int(s.split(separator: ":").last ?? "")
                continue
            }
            for prefix in ["SyntaxError:", "ReferenceError:", "TypeError:", "RangeError:", "Error:"] {
                if s.contains(prefix) {
                    diags.append(JSDiagnostic(message: s.trimmingCharacters(in: .whitespaces),
                                              line: pendingLine, severity: .error,
                                              sourceName: sourceName))
                    pendingLine = nil
                    break
                }
            }
        }
        if diags.isEmpty && !stderr.isEmpty {
            diags.append(JSDiagnostic(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                                      severity: .error, sourceName: sourceName))
        }
        return diags
    }

    /// Mutable box for pipe drains run on separate queues (avoids capturing
    /// `var`s across concurrent closures).
    private final class OutputCapture: @unchecked Sendable {
        var stdoutData = Data()
        var stderrData = Data()
    }

    private func emit(_ level: ConsoleLevel, _ message: String) {
        onConsoleEntry?(ConsoleEntry(level: level, message: message))
    }

    private func finish() {
        isRunning = false
        onFinish?()
    }
}
