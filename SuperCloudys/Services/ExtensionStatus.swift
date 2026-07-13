import AppKit
import Combine

@MainActor
final class ExtensionStatus: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var lastError: String?

    private var isChecking = false

    init() {
        checkStatus()
    }

    func checkStatus() {
        guard !isChecking else { return }
        isChecking = true
        DispatchQueue.global(qos: .utility).async {
            let result = Self.checkPluginKit()
            DispatchQueue.main.async {
                self.isEnabled = result.enabled
                self.lastError = result.error
                self.isChecking = false
            }
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func checkPluginKit() -> (enabled: Bool, error: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-p", "com.apple.FinderSync"]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            let deadline = Date().addingTimeInterval(2)
            while task.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard !task.isRunning else {
                task.terminate()
                return (false, "Finder 扩展状态查询超时")
            }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard task.terminationStatus == 0 else {
                let message = errorOutput.isEmpty
                    ? "Finder 扩展状态查询失败（\(task.terminationStatus)）"
                    : errorOutput
                return (false, message)
            }
            let enabled = output.components(separatedBy: .newlines).contains { line in
                let line = line.trimmingCharacters(in: .whitespaces)
                return line.hasPrefix("+") && line.contains(AppConstants.extensionBundleID)
            }
            return (enabled, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
