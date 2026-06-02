import Foundation

enum AppLocator {

    enum Location {
        case app(URL)
        case cli(String)
        case notFound
    }

    static func locate(_ app: ExternalApp) -> Location {
        let appURL = URL(fileURLWithPath: app.appPath)
        if FileManager.default.fileExists(atPath: appURL.path) {
            return .app(appURL)
        }

        let searchPaths = ["/usr/local/bin/", "/opt/homebrew/bin/"]
        for cli in app.cliNames {
            for prefix in searchPaths {
                let fullPath = prefix + cli
                if FileManager.default.isExecutableFile(atPath: fullPath) {
                    return .cli(fullPath)
                }
            }
            if let resolved = resolveViaWhich(cli) {
                return .cli(resolved)
            }
        }

        return .notFound
    }

    private static func resolveViaWhich(_ command: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }
}
