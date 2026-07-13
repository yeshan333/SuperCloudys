import Cocoa
import os

enum OpenAppAction {

    private static let log = Logger(subsystem: "com.yeshan333.SuperCloudys", category: "OpenApp")

    static func execute(app: ExternalApp, urls: [URL]) {
        let appURL = URL(fileURLWithPath: app.appPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            showNotFoundAlert(appName: app.name)
            return
        }
        openViaApp(appURL: appURL, urls: urls)
    }

    private static func openViaApp(appURL: URL, urls: [URL]) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: appURL,
            configuration: config
        ) { _, error in
            if let error {
                log.error("Cannot open selection with \(appURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                showAlert(
                    title: "无法通过 \(appURL.deletingPathExtension().lastPathComponent) 打开",
                    message: error.localizedDescription
                )
            }
        }
    }

    private static func showNotFoundAlert(appName: String) {
        showAlert(
            title: "未找到 \(appName)",
            message: "请确认 \(appName) 仍然存在，或在 SuperCloudys 菜单中重新添加。"
        )
    }

    private static func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}
