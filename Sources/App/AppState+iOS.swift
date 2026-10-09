#if os(iOS)
import UIKit
import PDFUnpackKit

/// The iOS counterparts of the macOS panels. Each action materializes the file when the user
/// picks it, not before.
extension AppState {
    func quickLook(_ file: EmbeddedFile) {
        QuickLookPresenter.shared.present(all: embeddedFiles, startingAt: file)
    }

    /// Export a copy through the Files picker. The picker asks before it replaces a file.
    func save(_ file: EmbeddedFile) {
        guard let url = materialize(file) else { return }
        presentOnTop(UIDocumentPickerViewController(forExporting: [url], asCopy: true))
    }

    /// File URLs, rather than `ShareLink`, let the share sheet match each file's real type.
    func share(_ file: EmbeddedFile) {
        guard let url = materialize(file) else { return }
        presentOnTop(UIActivityViewController(activityItems: [url], applicationActivities: nil))
    }

    private func materialize(_ file: EmbeddedFile) -> URL? {
        do {
            return try TempStore.shared.materialize(file)
        } catch {
            loadError = "Couldn’t prepare “\(file.name)”: \(error.localizedDescription)"
            return nil
        }
    }
}

/// Present `controller` over whatever is on screen. On iPad a share sheet is a popover and
/// needs an anchor; SwiftUI gives no view to anchor it to, so it floats in the window center.
@MainActor
func presentOnTop(_ controller: UIViewController) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    guard var top = scene?.keyWindow?.rootViewController else { return }
    while let presented = top.presentedViewController { top = presented }

    if let popover = controller.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
    top.present(controller, animated: true)
}
#endif
