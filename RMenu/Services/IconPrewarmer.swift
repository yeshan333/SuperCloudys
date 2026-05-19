import AppKit

/// 主 App 启动时后台预热 LaunchServices/UnifiedBufferCache,
/// 降低 Finder 扩展冷启动时 NSWorkspace.icon 的开销。
///
/// 注:macOS 的 pkd 完全控制 .appex 扩展进程的生命周期,
/// 我们无法强制扩展常驻。但 LaunchServices 是常驻 system service,
/// 主 App 触发的图标加载会让 .icns 文件页停留在 unified buffer cache,
/// 扩展冷启动时再访问会快很多。
enum IconPrewarmer {

    static func prewarmInBackground() {
        DispatchQueue.global(qos: .utility).async {
            let paths = collectAppPaths()
            for path in paths {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                _ = NSWorkspace.shared.icon(forFile: path)
            }
        }
    }

    private static func collectAppPaths() -> [String] {
        var paths = ExternalApp.allApps.map(\.appPath)
        paths.append(contentsOf: CustomAppStore.load().map(\.appPath))
        return paths
    }
}
