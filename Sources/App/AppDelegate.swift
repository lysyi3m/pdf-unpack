import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let services = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    /// Files opened via Finder Open-With, `open`, or double-click land here.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            AppState.shared.load(url: pdf)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.releaseSecurityScope()
        TempStore.shared.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
