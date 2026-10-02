import SwiftUI
import UniformTypeIdentifiers
import PDFUnpackKit

struct EmbeddedFileRow: View {
    let embeddedFile: EmbeddedFile

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(embeddedFile.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        #if os(macOS)
        // Drag a row straight out to Finder/Desktop. .draggable is reliable
        // inside a selectable List (unlike .onDrag); the file is materialized
        // lazily via the Transferable conformance.
        .draggable(embeddedFile)
        #endif
    }

    private var type: UTType {
        UTType(filenameExtension: (embeddedFile.name as NSString).pathExtension) ?? .data
    }

    #if os(macOS)
    private var icon: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: type))
            .resizable()
            .frame(width: 24, height: 24)
    }
    #else
    /// iOS has no public API for a type's document icon, so the row shows a symbol per family.
    private var icon: some View {
        Image(systemName: symbolName)
            .font(.title2)
            .foregroundStyle(.tint)
            .frame(width: 32)
    }

    private var symbolName: String {
        let families: [(UTType, String)] = [
            (.pdf, "doc.richtext"),
            (.image, "photo"),
            (.movie, "film"),
            (.audio, "waveform"),
            (.archive, "doc.zipper"),
            (.spreadsheet, "tablecells"),
            (.presentation, "rectangle.on.rectangle"),
            (.text, "doc.text"),
        ]
        return families.first { type.conforms(to: $0.0) }?.1 ?? "doc"
    }
    #endif

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(embeddedFile.size), countStyle: .file)
        guard let date = embeddedFile.modDate else { return size }
        return "\(size) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}
