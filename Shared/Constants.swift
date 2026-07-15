import Foundation

enum AppConstants {
    static let extensionBundleID = "com.yeshan333.SuperCloudys.FinderSyncExtension"
    static let appName = "SuperCloudys"
    static let urlScheme = "supercloudys"
}

struct ExternalApp {
    let name: String
    let bundleID: String
    let appPath: String

    static let vscode = ExternalApp(
        name: "VSCode",
        bundleID: "com.microsoft.VSCode",
        appPath: "/Applications/Visual Studio Code.app"
    )

    static let warp = ExternalApp(
        name: "Warp",
        bundleID: "dev.warp.Warp-Stable",
        appPath: "/Applications/Warp.app"
    )

    static let zed = ExternalApp(
        name: "Zed",
        bundleID: "dev.zed.Zed",
        appPath: "/Applications/Zed.app"
    )

    static let kaku = ExternalApp(
        name: "Kaku",
        bundleID: "fun.tw93.kaku",
        appPath: "/Applications/Kaku.app"
    )

    static let allApps: [ExternalApp] = [vscode, zed, warp, kaku]
}
