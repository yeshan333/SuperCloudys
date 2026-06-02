import Cocoa

enum OpenAppAction {

    static func execute(app: ExternalApp, urls: [URL]) {
        switch AppLocator.locate(app) {
        case .app(let appURL):
            openViaApp(appURL: appURL, urls: urls)
        case .cli(let cliPath):
            openViaCLI(cliPath: cliPath, urls: urls)
        case .notFound:
            showNotFoundAlert(appName: app.name)
        }
    }

    private static func openViaApp(appURL: URL, urls: [URL]) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
    }

    private static func openViaCLI(cliPath: String, urls: [URL]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: cliPath)
        task.arguments = urls.map { $0.path }
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
    }

    private static func showNotFoundAlert(appName: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "未找到 \(appName)"
            alert.informativeText = "请确认 \(appName) 已安装到 /Applications 目录。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }
}
