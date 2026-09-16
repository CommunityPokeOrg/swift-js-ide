import SwiftUI
import UniformTypeIdentifiers
import EditorCore

/// Root layout: sidebar file browser, tab strip + editor, bottom console/problems.
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        colorScheme == .dark ? HighlightTheme.dark : HighlightTheme.light
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VSplitView {
                editorArea
                    .frame(minHeight: 200)
                BottomPanelView()
                    .frame(minHeight: 120, idealHeight: 200, maxHeight: 340)
            }
            .toolbar { toolbarContent }
        }
        .fileImporter(
            isPresented: $appState.isFolderPickerPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                appState.openFolder(url)
            }
        }
        .fileImporter(
            isPresented: $appState.isImporterPresented,
            allowedContentTypes: [.javaScript, .plainText, .json, .sourceCode, .text],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                appState.importFiles(urls)
            }
        }
        .fileExporter(
            isPresented: $appState.isExporterPresented,
            document: TextFileDocument(text: appState.selectedDocument?.text ?? ""),
            contentType: .javaScript,
            defaultFilename: appState.selectedDocument?.displayName ?? "untitled.js"
        ) { result in
            if case let .success(url) = result {
                appState.exportCurrent(to: url)
            }
        }
        .alert("New File", isPresented: $appState.isNewFileAlertPresented) {
            TextField("File name", text: $appState.newFileName)
            Button("Create") {
                appState.createFileInWorkspace(named: appState.newFileName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Created in the workspace root.")
        }
        .alert("Error", isPresented: Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .onAppear {
            appState.restoreLastWorkspace()
            appState.loadDemoIfRequested()
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        if let doc = appState.selectedDocument {
            VStack(spacing: 0) {
                TabBarView()
                Divider()
                CodeEditor(
                    text: Binding(
                        get: { appState.selectedDocument?.text ?? "" },
                        set: { appState.updateText($0, for: doc.id) }
                    ),
                    palette: palette,
                    revealRequest: appState.revealRequest
                )
            }
        } else {
            VStack(spacing: 0) {
                TabBarView()
                Divider()
                WelcomeView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if appState.runState == .running {
                Button {
                    appState.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop (⌘.)")

                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    appState.run()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Run (⌘R)")
                .disabled(appState.selectedDocument == nil)
            }

            Button {
                appState.saveCurrent()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down.on.square")
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("Save (⌘S)")
            .disabled(appState.selectedDocument == nil)
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            Button {
                appState.newDocument()
            } label: {
                Label("New Script", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                appState.isImporterPresented = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }
    }
}
