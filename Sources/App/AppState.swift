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
    @Published var unlockError = false
    @Published var attachments: [Attachment] = []
    @Published var selection: Attachment.ID?
    @Published var loadError: String?

    private var extractor: PDFAttachmentExtractor?
    private var currentURL: URL?
    private var accessingScope = false

    var selectedAttachment: Attachment? {
        guard let selection else { return nil }
        return attachments.first { $0.id == selection }
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

    func submitPassword(_ password: String) {
        guard let extractor else { return }
        if extractor.unlock(password: password) {
            unlockError = false
            needsPassword = false
            finishLoading()
        } else {
            unlockError = true
        }
    }

    func cancelPassword() {
        reset()
    }

    private func finishLoading() {
        guard let extractor else { return }
        do {
            attachments = try extractor.extractAttachments().map(Attachment.init)
            selection = attachments.first?.id
        } catch {
            loadError = "Couldn’t read the embedded files in this PDF."
        }
    }

    private func reset() {
        if accessingScope, let url = currentURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessingScope = false
        currentURL = nil
        extractor = nil
        attachments = []
        selection = nil
        needsPassword = false
        unlockError = false
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

    func saveAll() {
        guard !attachments.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save All"
        panel.message = "Choose a folder to save all \(attachments.count) files into."

        guard panel.runModal() == .OK, let dir = panel.url else { return }

        var used = Set<String>()
        var failures = 0
        for att in attachments {
            let name = Filename.deduplicated(Filename.sanitized(att.name), taken: &used)
            do {
                try att.data.write(to: dir.appendingPathComponent(name))
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            loadError = "Saved \(attachments.count - failures) of \(attachments.count) files; \(failures) failed."
        }
    }
}
