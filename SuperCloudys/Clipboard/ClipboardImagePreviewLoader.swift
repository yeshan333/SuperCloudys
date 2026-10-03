import AppKit
import ImageIO

/// 串行解码预览，避免快速切换图片时同时展开多张原图。
actor ClipboardImagePreviewLoader {
    static let shared = ClipboardImagePreviewLoader()
    static let maxPixelDimension = 1024
    private let cache = NSCache<NSString, NSImage>()

    init() {
        cache.countLimit = 30
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func image(at path: String) -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: path) as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ), let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelDimension,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary), !Task.isCancelled else { return nil }

            let image = NSImage(cgImage: preview, size: NSSize(
                width: preview.width, height: preview.height
            ))
            cache.setObject(image, forKey: path as NSString,
                            cost: preview.bytesPerRow * preview.height)
            return image
        }
    }
}
