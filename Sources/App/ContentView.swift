import SwiftUI
import PDFUnpackKit

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        content
            .frame(minWidth: 720, minHeight: 460)
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
        NavigationSplitView {
            List(state.attachments, selection: $state.selection) { att in
                AttachmentRow(attachment: att)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 300)
            .overlay {
                if state.attachments.isEmpty {
                    ContentUnavailableView(
                        "No Embedded Files",
                        systemImage: "tray",
                        description: Text("This PDF has no document-level attachments. (Page-annotation and /AF files aren’t supported in v1.)")
                    )
                }
            }
        } detail: {
            PreviewContainer()
        }
        .navigationTitle(state.fileName ?? "PDF Unpack")
        .navigationSubtitle(itemCountText)
        .toolbar {
            ToolbarItemGroup {
                Button("Open…") { state.presentOpenPanel() }
                Button("Save All…") { state.saveAll() }
                    .disabled(state.attachments.isEmpty)
            }
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
