import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import SuperCloudys

final class ClipboardImagePreviewLoaderTests: XCTestCase {
    func testLargeImagePreviewFitsPixelLimitAndPreservesAspectRatioAndOriginalFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.png")
        try writeImage(to: url, width: 4096, height: 2048)
        let original = try Data(contentsOf: url)
        let loader = ClipboardImagePreviewLoader()

        let loaded = await loader.image(at: url.path)
        let image = try XCTUnwrap(loaded)
        let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        XCTAssertEqual(pixels.width, 1024)
        XCTAssertEqual(pixels.height, 512)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testSmallImagePreviewKeepsOriginalPixelDimensions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("small.png")
        try writeImage(to: url, width: 80, height: 40)
        let loaded = await ClipboardImagePreviewLoader().image(at: url.path)
        let image = try XCTUnwrap(loaded)
        let pixels = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(pixels.width, 80)
        XCTAssertEqual(pixels.height, 40)
    }

    func testMissingOrCorruptImageReturnsNoPreviewAndCanBeRetriedAfterRepair() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("repaired.png")
        let loader = ClipboardImagePreviewLoader()
        let missing = await loader.image(at: url.path)
        XCTAssertNil(missing)
        try Data("invalid image".utf8).write(to: url)
        let corrupt = await loader.image(at: url.path)
        XCTAssertNil(corrupt)
        try writeImage(to: url, width: 80, height: 40)
        let repaired = await loader.image(at: url.path)
        XCTAssertNotNil(repaired)
    }

    func testCancelledPreviewRequestReturnsNoImageEvenWhenPreviewIsCached() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cached.png")
        try writeImage(to: url, width: 80, height: 40)
        let loader = ClipboardImagePreviewLoader()
        let initial = await loader.image(at: url.path)
        XCTAssertNotNil(initial)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await loader.image(at: url.path)
        }
        let cancelled = await task.value
        XCTAssertNil(cancelled)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardPreviewTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeImage(to url: URL, width: Int, height: Int) throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
