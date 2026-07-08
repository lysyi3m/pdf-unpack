import AppKit

/// Backs the right-click ▸ Services ▸ "Open in PDF Unpack" item declared in
/// Info.plist (NSMessage = openInPDFUnpack).
final class ServicesProvider: NSObject {
    @objc func openInPDFUnpack(_ pboard: NSPasteboard,
                               userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        Task { @MainActor in
            AppState.shared.load(url: pdf)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
