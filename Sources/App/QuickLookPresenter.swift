import Quartz
import PDFUnpackKit

/// A single file handed to Quick Look. `previewItemURL` may be nil if the bytes
/// couldn't be materialized, in which case Quick Look shows its "no preview" state.
final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    init(url: URL?) { previewItemURL = url }
}

/// Drives the shared Quick Look panel (the spacebar-style floating window) over
/// the current embedded-file list. Materializes bytes to temp files lazily, only
/// for the item Quick Look actually asks to display. Left/right arrows in the
/// panel walk the whole list. Main-actor bound, like the `QLPreviewPanel` it drives.
///
/// `QLPreviewPanelDataSource` carries no isolation annotation, but the panel calls its data
/// source on the main thread. `@preconcurrency` records that; Swift traps at runtime if it ever
/// doesn't.
@MainActor
final class QuickLookPresenter: NSObject, @preconcurrency QLPreviewPanelDataSource,
    QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()

    private var items: [EmbeddedFile] = []

    /// Open Quick Look, or close it if already showing (Finder spacebar toggle).
    /// With 2+ files selected, preview just that selection; with 0–1 selected,
    /// preview the whole list so the arrow keys browse everything.
    func toggle(all embeddedFiles: [EmbeddedFile], selected: Set<EmbeddedFile.ID>) {
        guard !embeddedFiles.isEmpty else { return }

        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            return
        }

        guard let panel = QLPreviewPanel.shared() else { return }

        let selectedItems = embeddedFiles.filter { selected.contains($0.id) }
        let startIndex: Int
        if selectedItems.count >= 2 {
            items = selectedItems
            startIndex = 0
        } else {
            items = embeddedFiles
            startIndex = selectedItems.first.flatMap { sel in
                embeddedFiles.firstIndex { $0.id == sel.id }
            } ?? 0
        }

        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = startIndex
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        guard items.indices.contains(index) else { return PreviewItem(url: nil) }
        let url = try? TempStore.shared.materialize(items[index])
        return PreviewItem(url: url)
    }
}
