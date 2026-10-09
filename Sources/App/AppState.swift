#if os(macOS)
import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers
import PDFUnpackKit

/// Observable app model: current document, unlock flow, and the list of
/// extracted embedded files. Shared singleton so the AppDelegate and the Services
/// provider can drive it regardless of window/scene lifecycle timing.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var fileName: String?
    @Published var needsPassword = false
    @Published var embeddedFiles: [EmbeddedFile] = []
    @Published var selection: Set<EmbeddedFile.ID> = []
    @Published var loadError: String?
    /// True while a PDF is read or Save All writes. Both run off the main actor, because a
    /// file provider can make coordination wait for a download.
    @Published private(set) var isBusy = false

    private var extractor: EmbeddedFileExtractor?
    /// Identifies the latest load, so a slow read that a newer load or a close replaced is
    /// dropped when it finishes.
    private var loadToken = UUID()

    /// Selected embedded files, in list order.
    var selectedEmbeddedFiles: [EmbeddedFile] {
        embeddedFiles.filter { selection.contains($0.id) }
    }

    // MARK: - Loading

    func load(url: URL) {
        reset()
        let token = UUID()
        loadToken = token
        isBusy = true

        Task {
            let data = await Task.detached { Result { try Self.readCoordinated(url) } }.value
            guard loadToken == token else { return }
            isBusy = false

            do {
                let extractor = try EmbeddedFileExtractor(data: data.get())
                self.extractor = extractor
                self.fileName = url.lastPathComponent

                if extractor.isEncrypted && !extractor.isUnlocked {
                    needsPassword = true
                } else {
                    finishLoading()
                }
            } catch {
                fileName = nil
                loadError = "Couldn’t open “\(url.lastPathComponent)”. It may be corrupt or not a PDF."
            }
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
            embeddedFiles = try extractor.extractEmbeddedFiles().map(EmbeddedFile.init)
            selection = embeddedFiles.first.map { [$0.id] } ?? []
        } catch {
            // Release the document rather than leaving a half-loaded state alive, then
            // surface the error.
            reset()
            loadError = "Couldn’t read the embedded files in this PDF."
        }
    }

    /// Reads the whole PDF under file coordination. A security scope only grants permission;
    /// iCloud and third-party file providers also require coordinated access. The snapshot
    /// means a later unlock or extraction never touches the provider again.
    nonisolated private static func readCoordinated(_ url: URL) throws -> Data {
        // Opened, dropped and shared URLs are security-scoped under the sandbox.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private func reset() {
        loadToken = UUID()
        isBusy = false
        extractor = nil
        embeddedFiles = []
        selection = []
        needsPassword = false
        loadError = nil
        fileName = nil
    }

    // MARK: - Saving

    /// Write every embedded file into `dir` under a free name and return the URLs written.
    /// Failures surface through `loadError`. The writes run off the main actor.
    @discardableResult
    func saveAll(to dir: URL) async -> [URL] {
        let files = embeddedFiles
        isBusy = true
        let (written, failures) = await Task.detached { Self.write(files, into: dir) }.value
        isBusy = false

        if !failures.isEmpty {
            loadError = "Couldn’t save \(failures.count) of \(files.count) file(s) to \(dir.path):\n\(failures.joined(separator: "\n"))"
        }
        return written
    }

    /// Balances the folder's security scope itself, because the iOS folder picker returns a
    /// security-scoped URL, and coordinates the writes, because that folder can belong to a
    /// file provider.
    nonisolated private static func write(_ files: [EmbeddedFile], into dir: URL) -> (written: [URL], failures: [String]) {
        let accessing = dir.startAccessingSecurityScopedResource()
        defer { if accessing { dir.stopAccessingSecurityScopedResource() } }

        var written: [URL] = []
        var failures: [String] = []
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: dir, options: [], error: &coordinationError) {
            dir in
            var used = Set<String>()
            for file in files {
                let dest = uniqueDestination(for: file.name, in: dir, used: &used)
                do {
                    try file.data.write(to: dest)
                    written.append(dest)
                } catch {
                    failures.append("\(file.name): \(error.localizedDescription)")
                }
            }
        }
        if let coordinationError {
            failures = [coordinationError.localizedDescription]
        }
        return (written, failures)
    }

    #if os(macOS)
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

    func save(_ file: EmbeddedFile) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Filename.sanitized(file.name)
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try file.data.write(to: url)
            } catch {
                loadError = "Couldn’t save “\(file.name)”: \(error.localizedDescription)"
            }
        }
    }

    func toggleQuickLook() {
        QuickLookPresenter.shared.toggle(all: embeddedFiles, selected: selection)
    }

    func saveAll() {
        guard !embeddedFiles.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Save All"
        panel.message = "Choose a folder to save all \(embeddedFiles.count) files into."

        let response = panel.runModal()
        guard response == .OK else { return }
        // A directory NSOpenPanel can return a nil `url` when nothing is
        // explicitly highlighted; fall back to the folder being shown.
        guard let dir = panel.url ?? panel.directoryURL else {
            loadError = "Couldn’t determine the destination folder (panel returned no URL)."
            return
        }

        Task {
            let written = await saveAll(to: dir)
            if !written.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(written)
            }
        }
    }
    #endif

    /// A destination in `dir` that collides with neither files already on disk
    /// nor names used earlier in this same save. Case-insensitive to match
    /// typical macOS volumes; never overwrites an existing file.
    nonisolated private static func uniqueDestination(for rawName: String, in dir: URL, used: inout Set<String>) -> URL {
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
