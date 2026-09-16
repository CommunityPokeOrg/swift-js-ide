import SwiftUI

@main
struct PokeIDEApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 560)
                #endif
        }
        .commands {
            IDECommands(appState: appState)
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}

/// Menu-bar / hardware-keyboard commands, shared by macOS and iPadOS.
struct IDECommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Script") { appState.newDocument() }
                .keyboardShortcut("n", modifiers: .command)

            Button("New File in Workspace…") {
                appState.newFileName = "untitled.js"
                appState.isNewFileAlertPresented = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(appState.rootURL == nil)

            Divider()

            Button("Open Folder…") { appState.isFolderPickerPresented = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Import Files…") { appState.isImporterPresented = true }
                .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Save") { appState.saveCurrent() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.selectedDocument == nil)

            Button("Export Current…") { appState.isExporterPresented = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.selectedDocument == nil)

            Button("Close Tab") { appState.closeSelected() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(appState.selectedDocument == nil)
        }

        CommandMenu("Run") {
            Button("Run Script") { appState.run() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.selectedDocument == nil || appState.runState == .running)

            Button("Stop") { appState.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(appState.runState != .running)

            Divider()

            Button("Clear Console") { appState.clearConsole() }
                .keyboardShortcut("k", modifiers: .command)
        }
    }
}
