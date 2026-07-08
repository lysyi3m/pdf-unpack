import SwiftUI
import Quartz
import PDFUnpackKit

/// Right-hand detail pane: inline Quick Look of the selected attachment plus a
/// footer with its name/size and a Save button. Materializes the selection to a
/// temp file (Quick Look previews files on disk) whenever the selection changes.
struct PreviewContainer: View {
    @EnvironmentObject var state: AppState
    @State private var previewURL: URL?

    var body: some View {
        Group {
            if let att = state.selectedAttachment {
                VStack(spacing: 0) {
                    PreviewPane(url: previewURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    footer(att)
                }
            } else {
                ContentUnavailableView(
                    "Select a File",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose an embedded file on the left to preview it.")
                )
            }
        }
        .onChange(of: state.selection) { refresh() }
        .onChange(of: state.attachments.map(\.id)) { refresh() }
        .onAppear { refresh() }
    }

    private func footer(_ att: Attachment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(att.name).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(ByteCountFormatter.string(fromByteCount: Int64(att.size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save…") { state.save(att) }
        }
        .padding(12)
    }

    private func refresh() {
        if let att = state.selectedAttachment {
            previewURL = try? TempStore.shared.materialize(att)
        } else {
            previewURL = nil
        }
    }
}

final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    init(url: URL) { previewItemURL = url }
}

struct PreviewPane: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url.map { PreviewItem(url: $0) }
    }
}
