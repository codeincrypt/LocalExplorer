import AppKit
import SwiftUI
import ExplorerCore

@main
struct LocalExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services = AppServices.shared

    var body: some Scene {
        WindowGroup(AppConfiguration.productName, id: "explorer") {
            ExplorerWindowRoot()
                .environmentObject(services)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands { ExplorerCommands() }

        Settings {
            SettingsView()
                .environmentObject(services)
                .modifier(GlassThemeProvider(services: services))
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tabs are implemented inside the window; disable system window tabbing so
        // Command-T and Command-W stay unambiguous.
        NSWindow.allowsAutomaticWindowTabbing = false
        // Also works when launched as a bare executable (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        MainActor.assumeIsolated { AppServices.shared.applyAppearance() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppServices.shared.saveNow()
            AppServices.shared.access.stopAll()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Window root: owns the per-window model and wires it to the focused-scene system so
/// menu commands reach the active window.
struct ExplorerWindowRoot: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var model = WindowModel(initialURLs: WindowRestoration.takeInitialURLs())
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ExplorerWindowView(model: model, tab: model.activeTab)
            .modifier(GlassThemeProvider(services: services))
            .focusedSceneObject(model)
            .focusedSceneObject(model.activeTab)
            .background(WindowAccessor { window in
                GlassWindowConfigurator.configure(window)
                model.window = window
            })
            .onAppear { model.undoManager = undoManager }
            .onChange(of: undoManager) { _, newValue in model.undoManager = newValue }
            .navigationTitle(model.activeTab.title)
    }
}

/// Restores the previous session's tabs into the first window only.
@MainActor
enum WindowRestoration {
    private static var consumed = false

    static func takeInitialURLs() -> [URL]? {
        defer { consumed = true }
        guard !consumed, AppServices.shared.preferences.restoreTabs,
              AppConfiguration.environmentStartPath == nil else { return nil }
        let urls = AppServices.shared.state.openTabs.compactMap { path -> URL? in
            if ThisMac.isThisMac(URL(fileURLWithPath: path)) { return ThisMac.url }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return URL(fileURLWithPath: path)
        }
        return urls.isEmpty ? nil : urls
    }
}
