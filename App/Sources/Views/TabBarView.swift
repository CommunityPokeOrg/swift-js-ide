import SwiftUI
import EditorCore

/// Horizontal tab strip for open documents — touch-friendly on iPad,
/// compact on macOS.
struct TabBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(appState.documents) { doc in
                    TabChip(
                        document: doc,
                        isSelected: doc.id == appState.selectedDocumentID,
                        onSelect: { appState.select(doc) },
                        onClose: { appState.close(doc) }
                    )
                }
                Button {
                    appState.newDocument()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 30)
                }
                .buttonStyle(.plain)
                .help("New script (⌘N)")
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 36)
        .background(.bar)
    }
}

private struct TabChip: View {
    let document: ScriptDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHoveringClose = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(document.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
            if document.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Close Tab", action: onClose)
        }
    }
}
