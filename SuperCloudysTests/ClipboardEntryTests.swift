import XCTest
@testable import SuperCloudys

final class ClipboardEntryTests: XCTestCase {

    func testFingerprintDeterministic() {
        let fp1 = ClipboardEntry.fingerprint(type: .text, content: "hello")
        let fp2 = ClipboardEntry.fingerprint(type: .text, content: "hello")
        XCTAssertEqual(fp1, fp2)
    }

    func testFingerprintDiffersForDifferentContent() {
        let fp1 = ClipboardEntry.fingerprint(type: .text, content: "hello")
        let fp2 = ClipboardEntry.fingerprint(type: .text, content: "world")
        XCTAssertNotEqual(fp1, fp2)
    }

    func testFingerprintDiffersForDifferentType() {
        let fp1 = ClipboardEntry.fingerprint(type: .text, content: "hello")
        let fp2 = ClipboardEntry.fingerprint(type: .url, content: "hello")
        XCTAssertNotEqual(fp1, fp2)
    }

    func testFingerprintHandlesNilContent() {
        let fp = ClipboardEntry.fingerprint(type: .image, content: nil)
        XCTAssertFalse(fp.isEmpty)
    }

    func testCharacterCount() {
        let entry = makeEntry(plainText: "Hello, 世界!")
        XCTAssertEqual(entry.characterCount, 10)
    }

    func testCharacterCountNilWhenNoText() {
        let entry = makeEntry(plainText: nil)
        XCTAssertNil(entry.characterCount)
    }

    func testWordCount() {
        let entry = makeEntry(plainText: "git -C build/tadpole clean -fdx")
        XCTAssertEqual(entry.wordCount, 6)
    }

    func testWordCountSingleWord() {
        let entry = makeEntry(plainText: "hello")
        XCTAssertEqual(entry.wordCount, 1)
    }

    func testWordCountNilWhenEmpty() {
        let entry = makeEntry(plainText: "")
        XCTAssertNil(entry.wordCount)
    }

    func testCodableRoundTrip() throws {
        let entry = makeEntry(plainText: "test content")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ClipboardEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.contentType, entry.contentType)
        XCTAssertEqual(decoded.plainText, entry.plainText)
        XCTAssertEqual(decoded.title, entry.title)
        XCTAssertEqual(decoded.isPinned, entry.isPinned)
        XCTAssertEqual(decoded.fingerprint, entry.fingerprint)
    }

    // MARK: - Helpers

    private func makeEntry(plainText: String?) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(),
            contentType: .text,
            plainText: plainText,
            title: plainText ?? "Image",
            subtitle: nil,
            createdAt: Date(),
            sourceAppBundleID: "com.test.app",
            sourceAppName: "TestApp",
            isPinned: false,
            lastUsedAt: nil,
            fingerprint: ClipboardEntry.fingerprint(type: .text, content: plainText),
            imagePath: nil,
            thumbnailPath: nil,
            filePaths: nil,
            colorHex: nil
        )
    }
}
