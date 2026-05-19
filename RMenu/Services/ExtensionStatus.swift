import AppKit
import Combine

final class ExtensionStatus: ObservableObject {
    @Published var isEnabled = false

    private var timer: Timer?
    private var checkCount = 0

    init() {
        checkStatus()
        startAutoCheck()
    }

    deinit {
        timer?.invalidate()
    }

    func checkStatus() {
        let processRunning = checkProcessRunning()
        let pluginEnabled = checkPluginKit()
        DispatchQueue.main.async {
            self.isEnabled = processRunning || pluginEnabled
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 启动后前 30 秒每 3 秒检测一次，之后每 15 秒检测一次
    private func startAutoCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkCount += 1
            self.checkStatus()
            // 检测到已启用或已检测 10 次（30秒），切换为低频检测
            if self.isEnabled || self.checkCount >= 10 {
                self.timer?.invalidate()
                self.timer = Timer.scheduledTimer(
                    withTimeInterval: 15, repeats: true
                ) { [weak self] _ in
                    self?.checkStatus()
                }
            }
        }
    }

    private func checkProcessRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        return apps.contains { $0.bundleIdentifier == AppConstants.extensionBundleID }
    }

    private func checkPluginKit() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-p", "com.apple.FinderSync"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            for line in output.components(separatedBy: "\n") {
                if line.contains(AppConstants.extensionBundleID) {
                    return line.hasPrefix("+")
                }
            }
        } catch {}
        return false
    }
}
