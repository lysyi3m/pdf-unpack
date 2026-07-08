import SwiftUI
import UniformTypeIdentifiers
import PDFUnpackKit

struct AttachmentRow: View {
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // Drag a row straight out to Finder/Desktop. .draggable is reliable
        // inside a selectable List (unlike .onDrag); the file is materialized
        // lazily via the Transferable conformance.
        .draggable(attachment)
    }

    private var icon: NSImage {
        let ext = (attachment.name as NSString).pathExtension
        let type = UTType(filenameExtension: ext) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)
        guard let date = attachment.modDate else { return size }
        return "\(size) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
