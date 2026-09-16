import DefaultBackend
import Foundation
import GtkBackend
import SwiftCrossUI

import EditorCore

/// PokeIDE's Linux UI/testing runner — mirrors the SwiftUI layout with
/// SwiftCrossUI so the shared `EditorCore` model (tokenizer, themes, console,
/// diagnostics, document model) can be exercised and screenshotted on Linux.
///
/// Not a shipping target: a testing/CI aid. See Packages/LinuxRunner/README.md.
@main
struct PokeIDELinuxApp: App {
    // Unique GApplication id — the default `com.example.SwiftCrossUIApp`
    // collides with any other SCUI example running on the same session bus.
    var backend = GtkBackend(appIdentifier: "org.communitypoke.PokeIDE")

    var body: some Scene {
        WindowGroup("PokeIDE — Linux runner") {
            ContentView()
        }
        .defaultSize(width: 1180, height: 760)
    }
}

struct ContentView: View {
    @State var documents: [ScriptDocument]
    @State var selectedIndex = 0
    @State var consoleEntries: [ConsoleEntry]
    @State var problems: [JSDiagnostic] = []
    @State var running = false
    @State var editMode = false
    @State var bottomTab = 0
    let engine = NodeEngine()

    static let palette = HighlightTheme.dark

    init() {
        let source = Self.loadDemoSource()
        var doc = ScriptDocument(displayName: "demo.js", text: source)
        doc.isDirty = false
        _documents = State(wrappedValue: [doc])
        // Seed the console with a real `node` execution so first paint shows output.
        _consoleEntries = State(wrappedValue: NodeEngine.runSync(source))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            mainArea
        }
    }

    // MARK: - Sidebar

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PokeIDE")
                    .font(.headline)
                Spacer()
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Documents")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    ForEach(documents.indices, id: \.self) { index in
                        let doc = documents[index]
                        Button {
                            selectedIndex = index
                        } label: {
                            HStack {
                                Text(doc.displayName)
                                    .font(.system(size: 13))
                                Spacer()
                                if doc.isDirty {
                                    Text("●").foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                    }

                    Text("Workspace")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                    Text("(no folder open)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 210)
    }

    // MARK: - Main area

    var mainArea: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tabBar
            Divider()
            editorArea
            Divider()
            bottomPanel
        }
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            if running {
                Button("■ Stop") { engine.requestStop() }
            } else {
                Button("▶ Run") { run() }
            }
            Button("Clear Console") { consoleEntries = [] }
            Spacer()
            Toggle("Edit", isOn: $editMode)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(documents.indices, id: \.self) { index in
                    let selected = index == selectedIndex
                    Button {
                        selectedIndex = index
                    } label: {
                        HStack(spacing: 6) {
                            Text(documents[index].displayName)
                                .font(.system(size: 13))
                            if documents[index].isDirty {
                                Text("●").font(.system(size: 8)).foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selected ? Color(red: 0.35, green: 0.35, blue: 0.55) : Color.clear)
                        .cornerRadius(6)
                    }
                }
                Button("+") { addDocument() }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 36)
    }

    var editorArea: some View {
        Group {
            if documents.isEmpty {
                Spacer()
            } else if editMode {
                TextEditor(text: Binding(
                    get: { documents[selectedIndex].text },
                    set: { newText in
                        documents[selectedIndex].text = newText
                        documents[selectedIndex].isDirty = true
                    }
                ))
                .font(.system(size: 13, design: .monospaced))
            } else {
                HighlightedCodeView(source: documents[selectedIndex].text,
                                    palette: Self.palette)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var bottomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button("Console") { bottomTab = 0 }
                    .font(bottomTab == 0 ? .headline : .body)
                Button("Problems (\(problems.count))") { bottomTab = 1 }
                    .font(bottomTab == 1 ? .headline : .body)
                Spacer()
                Text("\(consoleEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            if bottomTab == 0 {
                consoleList
            } else {
                problemsList
            }
        }
        .frame(height: 220)
    }

    var consoleList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(consoleEntries.indices, id: \.self) { index in
                    let entry = consoleEntries[index]
                    HStack(alignment: .top, spacing: 8) {
                        Text("●")
                            .font(.system(size: 7))
                            .foregroundColor(color(for: entry.level))
                        Text(entry.message)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(color(for: entry.level))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var problemsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if problems.isEmpty {
                    Text("No problems detected")
                        .foregroundColor(.gray)
                        .padding(10)
                } else {
                    ForEach(problems.indices, id: \.self) { index in
                        let diag = problems[index]
                        HStack(alignment: .top, spacing: 8) {
                            Text("✖").foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text(diag.message).font(.system(size: 13))
                                Text(diag.locationDescription)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    func run() {
        guard !documents.isEmpty else { return }
        running = true
        let doc = documents[selectedIndex]
        problems = []
        engine.onConsoleEntry = { entry in
            DispatchQueue.main.async { self.consoleEntries.append(entry) }
        }
        engine.onDiagnostics = { diags in
            DispatchQueue.main.async { self.problems = diags }
        }
        engine.onFinish = {
            DispatchQueue.main.async { self.running = false }
        }
        consoleEntries = [ConsoleEntry(level: .system, message: "Running \(doc.displayName)…")]
        engine.evaluate(doc.text, named: doc.displayName)
    }

    func addDocument() {
        var doc = ScriptDocument(
            displayName: "untitled\(documents.count + 1).js",
            text: "// New script\nconsole.log('Hello');\n"
        )
        doc.isDirty = true
        documents.append(doc)
        selectedIndex = documents.count - 1
    }

    func color(for level: ConsoleLevel) -> Color {
        switch level {
        case .error: return .red
        case .warn: return .orange
        case .result: return .system(.blue)
        case .system: return .gray
        case .info: return .blue
        case .debug: return .purple
        case .log: return Color(white: 0.85)
        }
    }

    static func loadDemoSource() -> String {
        if let path = ProcessInfo.processInfo.environment["POKEIDE_SOURCE"],
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        for candidate in [
            "App/Resources/demo.js",
            "../App/Resources/demo.js",
            "../../App/Resources/demo.js"
        ] {
            if let text = try? String(contentsOfFile: candidate, encoding: .utf8) {
                return text
            }
        }
        return """
        // PokeIDE Linux runner
        console.log("Hello from node");
        const squares = [1, 2, 3, 4].map(n => n * n);
        console.info({ squares });
        """
    }
}
