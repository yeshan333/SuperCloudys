import Foundation

enum AppConstants {
    static let extensionBundleID = "com.yeshan333.SuperCloudys.FinderSyncExtension"
    static let appName = "SuperCloudys"
}

struct ExternalApp {
    let name: String
    let bundleID: String
    let appPath: String
    let cliNames: [String]

    static let vscode = ExternalApp(
        name: "VSCode",
        bundleID: "com.microsoft.VSCode",
        appPath: "/Applications/Visual Studio Code.app",
        cliNames: ["code"]
    )

    static let warp = ExternalApp(
        name: "Warp",
        bundleID: "dev.warp.Warp-Stable",
        appPath: "/Applications/Warp.app",
        cliNames: ["warp"]
    )

    static let zed = ExternalApp(
        name: "Zed",
        bundleID: "dev.zed.Zed",
        appPath: "/Applications/Zed.app",
        cliNames: ["zed"]
    )

    static let kaku = ExternalApp(
        name: "Kaku",
        bundleID: "fun.tw93.kaku",
        appPath: "/Applications/Kaku.app",
        cliNames: ["kaku"]
    )

    static let allApps: [ExternalApp] = [vscode, zed, warp, kaku]
}
