import SwiftUI
import EditorCore

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Bottom output panel: console transcript + problems list.
struct BottomPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection) {
                Text("Console").tag(0)
                Text("Problems (\(appState.diagnostics.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .padding(.vertical, 6)

            Divider()

            if selection == 0 {
                ConsoleView()
            } else {
                ProblemsView()
            }
        }
    }
}

struct ConsoleView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.consoleEntries) { entry in
                            ConsoleRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: appState.consoleEntries.count) { _ in
                    if let last = appState.consoleEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()
            HStack {
                Text("\(appState.consoleEntries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyAll()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                Button {
                    appState.clearConsole()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func copyAll() {
        let text = appState.consoleEntries.map(\.message).joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

private struct ConsoleRow: View {
    let entry: ConsoleEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 3)
            Text(entry.message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        switch entry.level {
        case .error: return .red
        case .warn: return .orange
        case .result: return .accentColor
        case .system: return .secondary
        case .info: return .blue
        case .debug: return .purple
        case .log: return .primary
        }
    }
}

struct ProblemsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.diagnostics.isEmpty {
                VStack {
                    Spacer()
                    Label("No problems detected", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(appState.diagnostics) { diagnostic in
                    Button {
                        appState.reveal(diagnostic)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: diagnostic.severity == .error
                                  ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(diagnostic.severity == .error ? Color.red : Color.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnostic.message)
                                    .font(.callout)
                                if !diagnostic.locationDescription.isEmpty {
                                    Text(diagnostic.locationDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }
}
