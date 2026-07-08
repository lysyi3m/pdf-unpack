import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFUnpackKit

/// Observable app model: current document, unlock flow, and the list of
/// extracted attachments. Shared singleton so the AppDelegate and the Services
/// provider can drive it regardless of window/scene lifecycle timing.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var fileName: String?
    @Published var needsPassword = false
    @Published var attachments: [Attachment] = []
    @Published var selection: Set<Attachment.ID> = []
    @Published var loadError: String?

    private var extractor: PDFAttachmentExtractor?
    private var currentURL: URL?
    private var accessingScope = false

    /// Selected attachments, in list order.
    var selectedAttachments: [Attachment] {
        attachments.filter { selection.contains($0.id) }
    }

    // MARK: - Loading

    func load(url: URL) {
        reset()

        // Dropped/opened URLs are security-scoped under the sandbox; balance this
        // with stopAccessing in reset() when the document is replaced.
        let accessing = url.startAccessingSecurityScopedResource()

        do {
            let extractor = try PDFAttachmentExtractor(url: url)
            self.extractor = extractor
            self.currentURL = url
            self.accessingScope = accessing
            self.fileName = url.lastPathComponent

            if extractor.isEncrypted && !extractor.isUnlocked {
                needsPassword = true
            } else {
                finishLoading()
            }
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            fileName = nil
            loadError = "Couldn’t open “\(url.lastPathComponent)”. It may be corrupt or not a PDF."
        }
    }

    /// Attempt to unlock with `password`. Returns false on the wrong password so
    /// the sheet can show its error without this type publishing during editing.
    @discardableResult
    func submitPassword(_ password: String) -> Bool {
        guard let extractor else { return false }
        guard extractor.unlock(password: password) else { return false }
        needsPassword = false
        finishLoading()
        return true
    }

    func cancelPassword() {
        reset()
    }

    /// Unload the current document and return to the empty/drop state.
    func closeDocument() {
        reset()
    }

    private func finishLoading() {
        guard let extractor else { return }
        do {
            attachments = try extractor.extractAttachments().map(Attachment.init)
            selection = attachments.first.map { [$0.id] } ?? []
        } catch {
            // Release the document + its security scope rather than leaving a
            // half-loaded state alive, then surface the error.
            reset()
            loadError = "Couldn’t read the embedded files in this PDF."
        }
    }

    /// Balance the active document's security-scoped access. Also called at app
    /// termination so the scope isn't left open when the process exits.
    func releaseSecurityScope() {
        if accessingScope, let url = currentURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessingScope = false
        currentURL = nil
    }

    private func reset() {
        releaseSecurityScope()
        extractor = nil
        attachments = []
        selection = []
        needsPassword = false
        loadError = nil
        fileName = nil
    }

    // MARK: - Panels

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func save(_ att: Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Filename.sanitized(att.name)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try att.data.write(to: url)
            } catch {
                loadError = "Couldn’t save “\(att.name)”: \(error.localizedDescription)"
            }
        }
    }

    func toggleQuickLook() {
        QuickLookPresenter.shared.toggle(all: attachments, selected: selection)
    }

    func saveAll() {
        guard !attachments.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save All"
        panel.message = "Choose a folder to save all \(attachments.count) files into."

        let response = panel.runModal()
        guard response == .OK else { return }
        // A directory NSOpenPanel can return a nil `url` when nothing is
        // explicitly highlighted; fall back to the folder being shown.
        guard let dir = panel.url ?? panel.directoryURL else {
            loadError = "Couldn’t determine the destination folder (panel returned no URL)."
            return
        }

        var used = Set<String>()
        var written: [URL] = []
        var failures: [String] = []
        for att in attachments {
            let dest = uniqueDestination(for: att.name, in: dir, used: &used)
            do {
                try att.data.write(to: dest)
                written.append(dest)
            } catch {
                failures.append("\(att.name): \(error.localizedDescription)")
            }
        }

        if !written.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(written)
        }
        if !failures.isEmpty {
            loadError = "Couldn’t save \(failures.count) of \(attachments.count) file(s) to \(dir.path):\n\(failures.joined(separator: "\n"))"
        }
    }

    /// A destination in `dir` that collides with neither files already on disk
    /// nor names used earlier in this same save. Case-insensitive to match
    /// typical macOS volumes; never overwrites an existing file.
    private func uniqueDestination(for rawName: String, in dir: URL, used: inout Set<String>) -> URL {
        let sanitized = Filename.sanitized(rawName)
        let ns = sanitized as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        let fm = FileManager.default

        var candidate = sanitized
        var i = 1
        while used.contains(candidate.lowercased())
                || fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            i += 1
            candidate = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
        }
        used.insert(candidate.lowercased())
        return dir.appendingPathComponent(candidate)
    }
}
