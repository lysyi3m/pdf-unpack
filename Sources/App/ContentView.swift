import SwiftUI
import PDFUnpackKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    /// Temp-file URL of the selected attachment for the native share menu.
    /// Updated off the render pass (in onChange) so we never do disk I/O inside
    /// body — that trips SwiftUI's "publishing during view updates" guard and
    /// corrupts List selection.
    @State private var shareURL: URL?

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
            .alert("Couldn’t open PDF", isPresented: loadErrorBinding) {
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
        List(state.attachments, selection: $state.selection) { att in
            AttachmentRow(attachment: att)
                .contextMenu {
                    Button("Quick Look") {
                        state.selection = att.id
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
        .onAppear { updateShareURL() }
        .onChange(of: state.selection) { updateShareURL() }
        .onChange(of: state.attachments.map(\.id)) { updateShareURL() }
        // Finder-style spacebar → Quick Look of the selected file.
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

                shareButton
            }
        }
    }

    // Always-present slot so the toolbar doesn't reflow: a live ShareLink when a
    // file is selected, otherwise an inert share button.
    @ViewBuilder
    private var shareButton: some View {
        if let url = shareURL {
            ShareLink(item: url)
        } else {
            Button {} label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(true)
        }
    }

    private func updateShareURL() {
        if let att = state.selectedAttachment {
            shareURL = try? TempStore.shared.materialize(att)
        } else {
            shareURL = nil
        }
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
