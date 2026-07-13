import SwiftUI

@main
struct SuperCloudysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dockMonitor = DockMonitor()
    @StateObject private var loginItem = LoginItemManager()

    init() {
        guard !Self.isRunningTests else { return }
        ClipboardHistoryController.shared.startMonitoring()
        ClipboardHotkeyManager.shared.register()
    }

    fileprivate static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(dockMonitor)
                .environmentObject(loginItem)
        } label: {
            Label(AppConstants.appName, systemImage: "folder.badge.gearshape")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        guard !SuperCloudysApp.isRunningTests else { return }
        ClipboardHistoryController.shared.flush()
    }
}
