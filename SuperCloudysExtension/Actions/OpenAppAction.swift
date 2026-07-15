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

        var components = URLComponents()
        components.scheme = AppConstants.urlScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "app", value: app.appPath)]
            + urls.map { URLQueryItem(name: "path", value: $0.path) }

        guard let requestURL = components.url, NSWorkspace.shared.open(requestURL) else {
            log.error("Cannot send open request to host app")
            showAlert(title: "无法启动 SuperCloudys", message: "请重新安装 SuperCloudys 后再试。")
            return
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
