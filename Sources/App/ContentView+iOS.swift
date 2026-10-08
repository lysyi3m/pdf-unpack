#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import PDFUnpackKit

/// The iOS window: one list without selection. A row tap opens Quick Look; each row's menu
/// saves or shares that one file, and the toolbar saves all of them.
struct ContentView: View {
    @EnvironmentObject var state: AppState

    private enum ImportTarget { case pdf, folder }

    @State private var showingImporter = false
    /// Kept after the importer closes, because its completion can run after the binding resets.
    @State private var importTarget = ImportTarget.pdf
    @State private var savedMessage: String?

    private var isLoaded: Bool { state.fileName != nil && !state.needsPassword }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(state.fileName ?? "PDF Unpack")
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .alert("PDF Unpack", isPresented: savedMessageBinding) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(savedMessage ?? "")
                }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importTarget == .pdf ? [.pdf] : [.folder]
        ) { result in
            switch (result, importTarget) {
            case (.success(let url), .pdf):
                state.load(url: url)
            case (.success(let url), .folder):
                saveAll(to: url)
            case (.failure(let error), _) where (error as? CocoaError)?.code == .userCancelled:
                break
            case (.failure(let error), .pdf):
                state.loadError = "Couldn’t open the PDF: \(error.localizedDescription)"
            case (.failure(let error), .folder):
                state.loadError = "Couldn’t open the folder: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $state.needsPassword) {
            PasswordSheet()
        }
        .alert("PDF Unpack", isPresented: loadErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.loadError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoaded {
            loadedView
        } else if state.needsPassword {
            // The title already names the locked PDF; the password sheet covers the rest.
            Color.clear
        } else {
            emptyView
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No PDF Open", systemImage: "doc.badge.plus")
        } description: {
            Text("See and save the files embedded inside a PDF.")
        } actions: {
            Button("Open PDF…") { present(.pdf) }
                .buttonStyle(.borderedProminent)
        }
        // App Review requires a privacy policy link inside the app (guideline 5.1.1(i)).
        .safeAreaInset(edge: .bottom) {
            Link("Privacy Policy", destination: privacyPolicyURL)
                .font(.footnote)
                .padding()
        }
    }

    private var loadedView: some View {
        List(state.embeddedFiles) { file in
            HStack {
                Button {
                    state.quickLook(file)
                } label: {
                    EmbeddedFileRow(embeddedFile: file)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    actions(for: file)
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .contextMenu { actions(for: file) }
        }
        .overlay {
            if state.embeddedFiles.isEmpty {
                ContentUnavailableView(
                    "No Embedded Files",
                    systemImage: "tray",
                    description: Text("This PDF doesn’t contain any embedded files.")
                )
            }
        }
    }

    @ViewBuilder
    private func actions(for file: EmbeddedFile) -> some View {
        Button("Quick Look", systemImage: "eye") { state.quickLook(file) }
        Button("Save…", systemImage: "square.and.arrow.down") { state.save(file) }
        Button("Share…", systemImage: "square.and.arrow.up") { state.share(file) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isLoaded {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close File", systemImage: "xmark") { state.closeDocument() }
            }
        }

        // The empty state carries its own Open button, so the toolbar shows these only with a
        // document open.
        if isLoaded {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Open…", systemImage: "folder") { present(.pdf) }

                if !state.embeddedFiles.isEmpty {
                    Button("Save All…", systemImage: "square.and.arrow.down.on.square") { present(.folder) }
                }
            }
        }
    }

    private func present(_ target: ImportTarget) {
        importTarget = target
        showingImporter = true
    }

    private func saveAll(to dir: URL) {
        let written = state.saveAll(to: dir)
        // A partial failure already raises the error alert, which counts the failures.
        guard !written.isEmpty, state.loadError == nil else { return }
        // No folder name: a provider's root folder has an on-disk name, not the one Files shows.
        savedMessage = "Saved \(count(written.count))."
    }

    private var subtitle: String {
        if state.needsPassword { return "Locked" }
        if isLoaded { return count(state.embeddedFiles.count) }
        return ""
    }

    private func count(_ n: Int) -> String {
        switch n {
        case 0: return "No files"
        case 1: return "1 file"
        default: return "\(n) files"
        }
    }

    private var loadErrorBinding: Binding<Bool> {
        Binding(
            get: { state.loadError != nil },
            set: { if !$0 { state.loadError = nil } }
        )
    }

    private var savedMessageBinding: Binding<Bool> {
        Binding(
            get: { savedMessage != nil },
            set: { if !$0 { savedMessage = nil } }
        )
    }
}
#endif
