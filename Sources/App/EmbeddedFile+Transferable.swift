import CoreTransferable
import UniformTypeIdentifiers
import PDFUnpackKit

/// Makes embedded files draggable out to Finder (and any file-accepting app). The
/// bytes are materialized to a temp file lazily — only when a drag is actually
/// performed and the destination requests the file. Conformance lives in the app
/// layer (not Kit) so it can use TempStore while keeping the core UI-free.
extension EmbeddedFile: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { embeddedFile in
            let url = try TempStore.shared.materialize(embeddedFile)
            return SentTransferredFile(url)
        }
        // Without this the drop lands as an extension-less "data" file, because
        // the exported type is generic public.data. The name carries the real
        // filename + extension for Finder — sanitized to match the Save flow.
        .suggestedFileName { Filename.sanitized($0.name) }
    }
}
