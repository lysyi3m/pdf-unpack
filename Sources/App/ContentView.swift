import SwiftUI
import AppKit
import PDFUnpackKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    /// The List binds its selection to view-local @State, not directly to
    /// AppState.selection. A List writes its selection binding *during* its own
    /// update pass; if that binding were an ObservableObject's @Published, the
    /// mid-render publish trips SwiftUI's "publishing during view updates" fault
    /// on every click. We mirror to/from AppState in onChange (post-update).
    @State private var selection: Set<Attachment.ID> = []

    var body: some View {
        content
            .frame(minWidth: 380, minHeight: 420)
            .dropDestination(for: URL.self) { urls, _ in
                guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
                state.load(url: pdf)
                return true
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
        if state.fileName != nil && !state.needsPassword {
            loadedView
        } else {
            DropView()
        }
    }

    private var loadedView: some View {
        List(state.attachments, selection: $selection) { att in
            AttachmentRow(attachment: att)
                .contextMenu {
                    Button("Quick Look") {
                        if !state.selection.contains(att.id) { state.selection = [att.id] }
                        state.toggleQuickLook()
                    }
                    Button("Save…") { state.save(att) }
                }
        }
        .overlay {
            if state.attachments.isEmpty {
                ContentUnavailableView(
                    "No Embedded Files",
                    systemImage: "tray",
                    description: Text("This PDF has no document-level attachments. (Page-annotation and /AF files aren’t supported in v1.)")
                )
            }
        }
        // Keep view-local selection and AppState.selection in sync, both writes
        // happening in onChange/onAppear (never during a render pass).
        .onAppear { if selection != state.selection { selection = state.selection } }
        .onChange(of: selection) {
            if state.selection != selection { state.selection = selection }
        }
        .onChange(of: state.selection) {
            if selection != state.selection { selection = state.selection }
        }
        // Finder-style spacebar → Quick Look of the selected file(s).
        .onKeyPress(.space) {
            state.toggleQuickLook()
            return .handled
        }
        .navigationTitle(state.fileName ?? "PDF Unpack")
        .navigationSubtitle(itemCountText)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.presentOpenPanel()
                } label: {
                    Label("Open…", systemImage: "folder")
                }

                Button {
                    state.saveAll()
                } label: {
                    Label("Save All…", systemImage: "square.and.arrow.down")
                }
                .disabled(state.attachments.isEmpty)

                Button {
                    shareSelection()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(state.selection.isEmpty)
            }
        }
    }

    /// Materialize the selected files lazily (on click) and present the native
    /// macOS share menu anchored near the toolbar. Doing this in an action —
    /// rather than precomputing URLs in onChange/@State — keeps disk I/O and
    /// state mutation out of the render pass entirely.
    private func shareSelection() {
        let urls = state.selectedAttachments.compactMap { try? TempStore.shared.materialize($0) }
        guard !urls.isEmpty, let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        let anchor = NSRect(x: view.bounds.maxX - 40, y: view.bounds.maxY, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
    }

    private var itemCountText: String {
        let n = state.attachments.count
        return n == 1 ? "1 file" : "\(n) files"
    }

    private var loadErrorBinding: Binding<Bool> {
        Binding(
            get: { state.loadError != nil },
            set: { if !$0 { state.loadError = nil } }
        )
    }
}
