import AppKit
import Combine

@MainActor
final class AppIconCache: ObservableObject {
    static let shared = AppIconCache()
    @Published private var revision = 0
    private let cache = NSCache<NSString, NSImage>()
    private var loadingPaths: Set<String> = []
    private let fallback = fallbackImage()

    private init() {
        cache.countLimit = 100
    }

    /// 原生菜单需要直接接收 Image；加载和刷新由缓存管理，不依赖图标子视图的 .task。
    func icon(forPath path: String) -> NSImage {
        guard !path.isEmpty else { return fallback }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        if loadingPaths.insert(path).inserted {
            Task { [weak self] in
                let image = await Task.detached(priority: .userInitiated) {
                    Self.loadIcon(forPath: path)
                }.value
                guard let self else { return }
                self.cache.setObject(image, forKey: path as NSString)
                self.loadingPaths.remove(path)
                self.revision &+= 1
            }
        }
        return fallback
    }

    func preload(paths: [String]) {
        for path in paths { _ = icon(forPath: path) }
    }

    nonisolated private static func loadIcon(forPath path: String) -> NSImage {
        guard FileManager.default.fileExists(atPath: path) else { return fallbackImage() }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    nonisolated private static func fallbackImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: 16, height: 16))
    }
}
