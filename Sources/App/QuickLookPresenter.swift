import Quartz
import PDFUnpackKit

/// A single file handed to Quick Look. `previewItemURL` may be nil if the bytes
/// couldn't be materialized, in which case Quick Look shows its "no preview" state.
final class PreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    init(url: URL?) { previewItemURL = url }
}

/// Drives the shared Quick Look panel (the spacebar-style floating window) over
/// the current attachment list. Materializes bytes to temp files lazily, only
/// for the item Quick Look actually asks to display. Left/right arrows in the
/// panel walk the whole list.
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()

    private var items: [Attachment] = []

    /// Open Quick Look on `selected` (or the first item), or close it if already
    /// showing — matching the Finder spacebar toggle.
    func toggle(attachments: [Attachment], selected: Attachment.ID?) {
        guard !attachments.isEmpty else { return }

        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            return
        }

        guard let panel = QLPreviewPanel.shared() else { return }
        items = attachments
        let startIndex = attachments.firstIndex { $0.id == selected } ?? 0

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
