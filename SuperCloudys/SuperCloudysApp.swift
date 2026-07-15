import SwiftUI
import os
import Carbon

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
    private static let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "OpenApp")

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: value),
              url.scheme == AppConstants.urlScheme,
              url.host == "open" else { return }
        Self.log.info("Received open request")
        handleOpenAppRequest(url)
    }

    private func handleOpenAppRequest(_ requestURL: URL) {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let appPath = queryItems.first(where: { $0.name == "app" })?.value,
              appPath.hasPrefix("/"),
              FileManager.default.fileExists(atPath: appPath) else { return }
        let urlPaths = queryItems.compactMap { $0.name == "path" ? $0.value : nil }
        guard !urlPaths.isEmpty, urlPaths.allSatisfy({ $0.hasPrefix("/") }) else { return }

        let appURL = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            urlPaths.map { URL(fileURLWithPath: $0) },
            withApplicationAt: appURL,
            configuration: config
        ) { _, error in
            if let error {
                Self.log.error("Cannot open selection with \(appPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !SuperCloudysApp.isRunningTests else { return }
        ClipboardHistoryController.shared.flush()
    }
}
