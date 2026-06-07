import SwiftUI

@main
struct SuperCloudysApp: App {
    @StateObject private var dockMonitor = DockMonitor()
    @StateObject private var loginItem = LoginItemManager()

    init() {
        IconPrewarmer.prewarmInBackground()
        guard !Self.isRunningTests else { return }
        ClipboardHistoryController.shared.startMonitoring()
        ClipboardHotkeyManager.shared.register()
    }

    private static var isRunningTests: Bool {
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
