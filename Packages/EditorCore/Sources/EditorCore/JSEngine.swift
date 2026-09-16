import Foundation

/// Abstraction over an embedded JavaScript runtime.
///
/// Handlers (`onConsoleEntry`, `onDiagnostics`, `onFinish`) are invoked on the
/// engine's private queue — callers that touch UI state must hop to the main actor.
public protocol JSEvaluating: AnyObject {
    var onConsoleEntry: ((ConsoleEntry) -> Void)? { get set }
    var onDiagnostics: (([JSDiagnostic]) -> Void)? { get set }
    var onFinish: (() -> Void)? { get set }

    var isRunning: Bool { get }

    /// Evaluates a script on the engine's own queue. Console output and
    /// exceptions are reported through the handlers.
    func evaluate(_ source: String, named name: String)

    /// Requests cancellation. Bridged callbacks stop delivering output and the
    /// next native bridge call throws back into JS. Note: JavaScriptCore cannot
    /// interrupt a tight `while (true)` loop with no bridge calls — the context
    /// is detached and its output discarded instead.
    func requestStop()

    /// Parses a script without executing it. Returns a diagnostic on failure.
    func checkSyntax(_ source: String, named name: String) -> JSDiagnostic?
}

/// Creates the platform-appropriate engine.
public enum JSEngineFactory {
    public static func makeEngine() -> JSEvaluating {
        #if canImport(JavaScriptCore)
        return JavaScriptCoreEngine()
        #else
        return UnavailableEngine()
        #endif
    }
}

#if canImport(JavaScriptCore)
import JavaScriptCore

/// JavaScript runtime backed by Apple's embedded JavaScriptCore (`JSContext`).
///
/// Each `evaluate` creates a fresh `JSContext` on the engine's serial queue, so
/// runs are isolated from each other and from the UI. `console.*`, `print`,
/// `setTimeout`-free synchronous evaluation only — no DOM or Node APIs.
public final class JavaScriptCoreEngine: JSEvaluating {

    private let queue = DispatchQueue(label: "org.communitypoke.pokeide.engine", qos: .userInitiated)
    private var generation = 0
    private var cancelled = false
    private var activeContext: JSContext?

    public private(set) var isRunning = false

    public var onConsoleEntry: ((ConsoleEntry) -> Void)?
    public var onDiagnostics: (([JSDiagnostic]) -> Void)?
    public var onFinish: (() -> Void)?

    public init() {}

    public func evaluate(_ source: String, named name: String) {
        queue.async { [self] in
            generation &+= 1
            let gen = generation
            cancelled = false
            isRunning = true

            let context = JSContext(virtualMachine: JSVirtualMachine())
            context?.name = name
            activeContext = context
            installBridges(in: context, generation: gen)

            context?.exceptionHandler = { [weak self] _, exception in
                guard let self, self.generation == gen, !self.cancelled, let exception else { return }
                self.onDiagnostics?([Self.diagnostic(from: exception, sourceName: name)])
            }

            let sourceURL = URL(string: "pokeide://\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")
            let result = context?.evaluateScript(source, withSourceURL: sourceURL)

            if generation == gen && !cancelled, let result, !result.isUndefined {
                emit(.result, "⇒ \(result.toString() ?? "undefined")")
            }
            finish()
        }
    }

    public func requestStop() {
        queue.async { [self] in
            cancelled = true
            // Signal to bridged callbacks so the next console call throws.
            activeContext?.setObject(true, forKeyedSubscript: "__pokeCancelled" as NSString)
            if isRunning {
                emit(.system, "Stop requested — run will halt at the next bridge call.")
            }
            finish()
        }
    }

    /// Uses the `JSCheckScriptSyntax` C API so callers can lint without running.
    public func checkSyntax(_ source: String, named name: String) -> JSDiagnostic? {
        guard let context = JSContext(), let global = context.jsGlobalContextRef else { return nil }
        let script = JSStringCreateWithCFString(source as CFString)
        let urlString = JSStringCreateWithCFString(name as CFString)
        defer {
            JSStringRelease(script)
            JSStringRelease(urlString)
        }
        var exception: JSValueRef?
        let ok = JSCheckScriptSyntax(global, script, urlString, 0, &exception)
        guard !ok, let exception else { return nil }
        guard let value = JSValue(jsValueRef: exception, in: context) else { return nil }
        return Self.diagnostic(from: value, sourceName: name)
    }

    // MARK: - Private

    private func installBridges(in context: JSContext?, generation gen: Int) {
        guard let context else { return }

        // Formatter used by the JS-side console implementation.
        context.evaluateScript("""
        function __pokeFormat(value) {
            if (value instanceof Error) { return value.name + ': ' + value.message; }
            if (typeof value === 'object' && value !== null) {
                try { return JSON.stringify(value); } catch (e) { return String(value); }
            }
            if (typeof value === 'undefined') { return 'undefined'; }
            return String(value);
        }
        """)

        // The bridged array must arrive as one JSValue — declaring `[JSValue]`
        // makes JSC bridge elements to native NSStrings and crash on cast.
        func makeLogHandler(_ level: ConsoleLevel) -> @convention(block) (JSValue) -> Void {
            return { [weak self] value in
                guard let self, self.generation == gen, !self.cancelled else {
                    if let ctx = JSContext.current() {
                        ctx.setObject(JSValue(newErrorFromMessage: "Execution cancelled", in: ctx),
                                      forKeyedSubscript: "__pokeInterrupt" as NSString)
                    }
                    return
                }
                let text = (value.toArray() ?? []).map { "\($0)" }.joined(separator: " ")
                self.emit(level, text)
            }
        }

        // JavaScriptCore drops extra arguments on fixed-arity bridged blocks, so the
        // native side takes a bridged array prepared by a thin JS wrapper.
        context.setObject(makeLogHandler(.log), forKeyedSubscript: "__pokeLog" as NSString)
        context.setObject(makeLogHandler(.info), forKeyedSubscript: "__pokeInfo" as NSString)
        context.setObject(makeLogHandler(.debug), forKeyedSubscript: "__pokeDebug" as NSString)
        context.setObject(makeLogHandler(.warn), forKeyedSubscript: "__pokeWarn" as NSString)
        context.setObject(makeLogHandler(.error), forKeyedSubscript: "__pokeError" as NSString)
        context.setObject(makeLogHandler(.log), forKeyedSubscript: "print" as NSString)

        context.evaluateScript("""
        (function() {
            function send(fn) {
                return function() {
                    if (typeof __pokeCancelled !== 'undefined' && __pokeCancelled === true) {
                        throw new Error('Execution cancelled');
                    }
                    fn(Array.prototype.map.call(arguments, __pokeFormat));
                };
            }
            console = {
                log: send(__pokeLog), info: send(__pokeInfo), debug: send(__pokeDebug),
                warn: send(__pokeWarn), error: send(__pokeError)
            };
            var __nativePrint = print;
            print = send(__nativePrint);
        })();
        """)
    }

    private func emit(_ level: ConsoleLevel, _ message: String) {
        onConsoleEntry?(ConsoleEntry(level: level, message: message))
    }

    private func finish() {
        isRunning = false
        activeContext = nil
        onFinish?()
    }

    static func diagnostic(from exception: JSValue, sourceName: String) -> JSDiagnostic {
        let message = exception.objectForKeyedSubscript("message")?.toString()
            ?? exception.toString()
            ?? "JavaScript error"
        let line = exception.objectForKeyedSubscript("line")?.toNumber()?.intValue
        let column = exception.objectForKeyedSubscript("column")?.toNumber()?.intValue
        return JSDiagnostic(
            message: message,
            line: line.flatMap { $0 > 0 ? $0 : nil },
            column: column.flatMap { $0 > 0 ? $0 : nil },
            severity: .error,
            sourceName: sourceName
        )
    }
}
#endif

/// Fallback used on platforms without JavaScriptCore (e.g. Linux CI for the
/// shared-core test suite — the app itself is never shipped there).
public final class UnavailableEngine: JSEvaluating {
    public var onConsoleEntry: ((ConsoleEntry) -> Void)?
    public var onDiagnostics: (([JSDiagnostic]) -> Void)?
    public var onFinish: (() -> Void)?
    public private(set) var isRunning = false

    public init() {}

    public func evaluate(_ source: String, named name: String) {
        isRunning = true
        onConsoleEntry?(ConsoleEntry(level: .system,
                                     message: "JavaScript runtime is not available on this platform."))
        isRunning = false
        onFinish?()
    }

    public func requestStop() {}

    public func checkSyntax(_ source: String, named name: String) -> JSDiagnostic? { nil }
}
