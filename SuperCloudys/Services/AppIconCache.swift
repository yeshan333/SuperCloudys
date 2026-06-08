import AppKit

final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 100
    }

    func icon(forPath path: String) async -> NSImage {
        if path.isEmpty {
            return Self.fallbackImage()
        }
        
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        let image = await Task.detached(priority: .userInitiated) {
            if FileManager.default.fileExists(atPath: path) {
                let nsImage = NSWorkspace.shared.icon(forFile: path)
                nsImage.size = NSSize(width: 16, height: 16)
                return nsImage
            }
            return Self.fallbackImage()
        }.value

        cache.setObject(image, forKey: path as NSString)
        return image
    }
    
    private static func fallbackImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: 16, height: 16))
    }
}
