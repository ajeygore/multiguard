import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    static let mainWindowID = "main"

    /// Captured from the main view so the delegate can reopen the Window scene (e.g. on Dock/Finder reopen).
    static var openWindow: OpenWindowAction?

    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        // Show a Dock / Cmd-Tab entry whenever the main window is in use…
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.isMainWindow(window) else { return }
            self?.setActivationPolicy(.regular)
        })
        // …and drop back to a pure menu-bar app once it is closed.
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, Self.isMainWindow(window) else { return }
            DispatchQueue.main.async {
                if !Self.hasVisibleMainWindow(excluding: window) {
                    self?.setActivationPolicy(.accessory)
                }
            }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Window scene opens on launch; make sure the app is a normal, activatable app at that point.
        if Self.hasVisibleMainWindow() {
            setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching the app again (Finder, Spotlight, `open -a`) while it lives in the menu bar: show the window.
        if !flag {
            Self.showMainWindow()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app alive when the main window is closed so the menu bar extra keeps running.
        return false
    }

    /// Bring the single main window to the front, creating it if needed, and make the app a regular app.
    @MainActor
    static func showMainWindow(openWindow: OpenWindowAction? = nil) {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: isMainWindow) {
            window.makeKeyAndOrderFront(nil)
        } else if let openWindow = openWindow ?? Self.openWindow {
            openWindow(id: mainWindowID)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// The SwiftUI `Window(id: "main")` scene; excludes the menu bar extra panel and popovers.
    private static func isMainWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        if let identifier = window.identifier?.rawValue, identifier.hasPrefix(mainWindowID) {
            return true
        }
        return window.styleMask.contains(.titled) && window.styleMask.contains(.closable) && window.title == "MultiGuard"
    }

    private static func hasVisibleMainWindow(excluding: NSWindow? = nil) -> Bool {
        NSApp.windows.contains { $0 !== excluding && isMainWindow($0) && $0.isVisible }
    }
}

@main
struct MultiGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // `Window` (not `WindowGroup`) so openWindow(id:) reuses the one main window instead of spawning another.
        Window("MultiGuard", id: AppDelegate.mainWindowID) {
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
