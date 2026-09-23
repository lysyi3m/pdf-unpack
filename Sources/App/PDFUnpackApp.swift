import SwiftUI
import AppKit

@main
struct PDFUnpackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    // One window, one document: AppState holds a single document, and Open With, Services,
    // drag-and-drop and File ▸ Open all load into it. A WindowGroup would open a new window
    // for every file Finder hands over, each rendering the same shared state.
    var body: some Scene {
        Window("PDF Unpack", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 380, minHeight: 420)
        }
        .defaultSize(width: 800, height: 520)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About PDF Unpack") { showAboutPanel() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") { state.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Look") { state.toggleQuickLook() }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(state.selection.isEmpty)
            }
            // App Review requires a privacy policy link inside the app (guideline 5.1.1(i)).
            CommandGroup(replacing: .help) {
                Link("Privacy Policy", destination: URL(string: "https://github.com/lysyi3m/pdf-unpack/blob/master/PRIVACY.md")!)
            }
        }
    }
}

/// Standard About panel (icon / name / version / copyright) plus a centered
/// credits block with a clickable link to the project repo.
@MainActor
private func showAboutPanel() {
    let credits = NSMutableAttributedString(
        string: "Extract the files embedded inside a PDF.\n\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    )
    credits.append(NSAttributedString(
        string: "github.com/lysyi3m/pdf-unpack",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://github.com/lysyi3m/pdf-unpack")!,
        ]
    ))
    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))

    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate(ignoringOtherApps: true)
}
