import SwiftUI

@main
struct PDFUnpackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 380, minHeight: 420)
        }
        .defaultSize(width: 800, height: 520)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { state.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Look") { state.toggleQuickLook() }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(state.selection.isEmpty)
            }
        }
    }
}
