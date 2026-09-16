import SwiftUI
import EditorCore

/// Project file browser + open-documents list.
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var renamingNode: FileNode?
    @State private var renameText = ""
    @State private var deletingNode: FileNode?

    var body: some View {
        List {
            if let root = appState.rootNode {
                Section {
                    OutlineGroup(root.children ?? [], children: \.children) { node in
                        FileRow(node: node)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !node.isDirectory {
                                    appState.openFile(at: node.url)
                                }
                            }
                            .contextMenu {
                                if !node.isDirectory {
                                    Button("Open") { appState.openFile(at: node.url) }
                                }
                                Button("Rename…") {
                                    renamingNode = node
                                    renameText = node.name
                                }
                                Button("Delete", role: .destructive) {
                                    deletingNode = node
                                }
                            }
                    }
                } header: {
                    Text(root.name)
                }
            }

            if !appState.documents.isEmpty {
                Section("Open Documents") {
                    ForEach(appState.documents) { doc in
                        Label(doc.displayName, systemImage: "doc.text")
                            .onTapGesture { appState.select(doc) }
                    }
                }
            }

            if appState.rootNode == nil {
                Section {
                    Label("No workspace open", systemImage: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PokeIDE")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Button("New File in Workspace…") {
                        appState.newFileName = "untitled.js"
                        appState.isNewFileAlertPresented = true
                    }
                    .disabled(appState.rootURL == nil)
                    Button("New Untitled Script") { appState.newDocument() }
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    appState.isFolderPickerPresented = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open folder (⌘⇧O)")
                Button {
                    appState.isImporterPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import files (⌘I)")
            }
        }
        .alert("Rename", isPresented: Binding(
            get: { renamingNode != nil },
            set: { if !$0 { renamingNode = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let node = renamingNode, !renameText.isEmpty {
                    appState.rename(node: node, to: renameText)
                }
                renamingNode = nil
            }
            Button("Cancel", role: .cancel) { renamingNode = nil }
        }
        .alert("Delete \(deletingNode?.name ?? "")?", isPresented: Binding(
            get: { deletingNode != nil },
            set: { if !$0 { deletingNode = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let node = deletingNode {
                    appState.delete(node: node)
                }
                deletingNode = nil
            }
            Button("Cancel", role: .cancel) { deletingNode = nil }
        } message: {
            Text("This can't be undone.")
        }
    }
}

private struct FileRow: View {
    let node: FileNode

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        if node.isDirectory { return "folder" }
        switch node.url.pathExtension.lowercased() {
        case "js", "mjs", "cjs", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "md", "txt": return "doc.text"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        node.isDirectory ? .accentColor : .secondary
    }
}
