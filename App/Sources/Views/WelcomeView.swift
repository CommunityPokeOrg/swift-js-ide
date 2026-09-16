import SwiftUI

/// Empty state shown when no document is open.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Image("AppIconImage")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(radius: 8)

            VStack(spacing: 6) {
                Text("PokeIDE")
                    .font(.largeTitle.bold())
                Text("A JavaScript playground for macOS & iPadOS")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                WelcomeButton(title: "New Script", systemImage: "plus.square") {
                    appState.newDocument()
                }
                WelcomeButton(title: "Open Folder", systemImage: "folder") {
                    appState.isFolderPickerPresented = true
                }
                WelcomeButton(title: "Import Files", systemImage: "square.and.arrow.down") {
                    appState.isImporterPresented = true
                }
            }

            VStack(spacing: 4) {
                Text("⌘R Run   ⌘. Stop   ⌘S Save")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WelcomeButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(width: 220, alignment: .leading)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
