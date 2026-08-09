import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app alive when the main window is closed so the menu bar extra keeps running.
        return false
    }
}

@main
struct MultiGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("MultiGuard", systemImage: "lock.shield") {
            MenuBarView(viewModel: AppState.shared.viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
