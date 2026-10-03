import XCTest
@testable import SuperCloudys

final class ClipboardStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: ClipboardStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardStoreTests_\(UUID().uuidString)")
        store = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
    }

    override func tearDown() {
        store.flush()
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInsertAndRetrieve() {
        let entry = makeEntry(text: "hello")
        store.insert(entry)
        XCTAssertEqual(store.allEntries.count, 1)
        XCTAssertEqual(store.allEntries.first?.plainText, "hello")
    }

    func testDeduplication() {
        let e1 = makeEntry(text: "same")
        let e2 = makeEntry(text: "same")
        store.insert(e1)
        store.insert(e2)
        XCTAssertEqual(store.allEntries.count, 1, "Duplicate should not create a new entry")
    }

    func testDifferentContentNotDeduplicated() {
        store.insert(makeEntry(text: "aaa"))
        store.insert(makeEntry(text: "bbb"))
        XCTAssertEqual(store.allEntries.count, 2)
    }

    func testCopyingDifferentTextsWithCollidingFingerprintsPreservesBothAfterRestart() {
        let first = makeEntry(text: "Ab")
        let second = makeEntry(text: "BA")
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        store.insert(first)
        store.insert(second)
        store.flush()

        let reloaded = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        XCTAssertEqual(reloaded.allEntries.compactMap(\.plainText), ["BA", "Ab"])
    }

    func testCopyingSameTextWithDifferentTypesAndMatchingFingerprintsKeepsBoth() {
        store.insert(makeEntry(text: "same", type: .text, fingerprint: "collision"))
        store.insert(makeEntry(text: "same", type: .url, fingerprint: "collision"))

        XCTAssertEqual(store.allEntries.map(\.contentType), [.url, .text])
    }

    func testDeleteById() {
        let entry = makeEntry(text: "to delete")
        store.insert(entry)
        XCTAssertEqual(store.allEntries.count, 1)
        store.delete(id: entry.id)
        XCTAssertEqual(store.allEntries.count, 0)
    }

    func testTogglePin() {
        let entry = makeEntry(text: "pin me")
        store.insert(entry)
        XCTAssertFalse(store.allEntries.first!.isPinned)
        store.togglePin(id: entry.id)
        XCTAssertTrue(store.allEntries.first!.isPinned)
        store.togglePin(id: entry.id)
        XCTAssertFalse(store.allEntries.first!.isPinned)
    }

    func testMarkUsedUpdatesTimestamp() {
        let entry = makeEntry(text: "used")
        store.insert(entry)

        store.markUsed(id: entry.id)

        XCTAssertNotNil(store.allEntries.first?.lastUsedAt)
    }

    func testClearUnpinnedPreservesPinned() {
        let pinned = makeEntry(text: "pinned")
        let unpinned = makeEntry(text: "unpinned")
        store.insert(pinned)
        store.togglePin(id: pinned.id)
        store.insert(unpinned)
        XCTAssertEqual(store.allEntries.count, 2)

        store.clearUnpinned()
        XCTAssertEqual(store.allEntries.count, 1)
        XCTAssertEqual(store.allEntries.first?.plainText, "pinned")
    }

    func testClearAllRemovesEverything() {
        store.insert(makeEntry(text: "a"))
        store.insert(makeEntry(text: "b"))
        store.clearAll()
        XCTAssertTrue(store.allEntries.isEmpty)
    }

    func testSearchByText() {
        store.insert(makeEntry(text: "git commit -m 'fix'"))
        store.insert(makeEntry(text: "https://example.com"))
        let results = store.search(query: "git")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results.first!.plainText!.contains("git"))
    }

    func testSearchCaseInsensitive() {
        store.insert(makeEntry(text: "Hello World"))
        let results = store.search(query: "hello")
        XCTAssertEqual(results.count, 1)
    }

    func testFilterByType() {
        store.insert(makeEntry(text: "text", type: .text))
        store.insert(makeEntry(text: "https://x.com", type: .url))
        let urls = store.filter(by: .url)
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.contentType, .url)
    }

    func testMaxEntriesTrimsOldest() {
        for i in 0..<15 {
            store.insert(makeEntry(text: "item \(i)"))
        }
        XCTAssertLessThanOrEqual(store.allEntries.count, 10)
    }

    func testRetentionRemovesOld() {
        var old = makeEntry(text: "old")
        old = ClipboardEntry(
            id: old.id, contentType: old.contentType, plainText: old.plainText,
            title: old.title, subtitle: old.subtitle,
            createdAt: Date().addingTimeInterval(-86400 * 10),
            sourceAppBundleID: old.sourceAppBundleID, sourceAppName: old.sourceAppName,
            isPinned: false, lastUsedAt: nil, fingerprint: "unique_old",
            imagePath: nil, thumbnailPath: nil, filePaths: nil, colorHex: nil
        )
        store.insert(old)
        store.insert(makeEntry(text: "recent"))
        XCTAssertEqual(store.allEntries.count, 2)

        store.applyRetention(maxAge: 86400 * 7)
        XCTAssertEqual(store.allEntries.count, 1)
        XCTAssertEqual(store.allEntries.first?.plainText, "recent")
    }

    func testRetentionKeepsRecentlyUsedOldEntry() {
        let oldButUsed = ClipboardEntry(
            id: UUID(), contentType: .text, plainText: "old but used", title: "old but used",
            subtitle: nil, createdAt: Date().addingTimeInterval(-86400 * 10),
            sourceAppBundleID: nil, sourceAppName: nil, isPinned: false,
            lastUsedAt: Date(), fingerprint: "old_but_used", imagePath: nil,
            thumbnailPath: nil, filePaths: nil, colorHex: nil
        )
        store.insert(oldButUsed)

        store.applyRetention(maxAge: 86400 * 7)

        XCTAssertEqual(store.allEntries.first?.id, oldButUsed.id)
    }

    func testPersistenceAcrossInstances() {
        store.insert(makeEntry(text: "persist"))
        store.flush()
        let store2 = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        XCTAssertEqual(store2.allEntries.count, 1)
        XCTAssertEqual(store2.allEntries.first?.plainText, "persist")
    }

    func testStartupRemovesOnlyUnreferencedAssets() throws {
        let referenced = store.assetsDirectory.appendingPathComponent("referenced.png")
        let orphaned = store.assetsDirectory.appendingPathComponent("orphaned.png")
        try Data([1]).write(to: referenced)
        store.insert(makeImageEntry(fingerprint: "kept", original: referenced.path))
        store.flush()
        try Data([2]).write(to: orphaned)

        _ = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphaned.path))
    }

    func testDeletingImageRemovesItsAssets() throws {
        let original = store.assetsDirectory.appendingPathComponent("image.png")
        let thumbnail = store.assetsDirectory.appendingPathComponent("image_thumb.png")
        try Data([1]).write(to: original)
        try Data([2]).write(to: thumbnail)
        let entry = makeImageEntry(
            fingerprint: "image-1",
            original: original.path,
            thumbnail: thumbnail.path
        )

        store.insert(entry)
        store.delete(id: entry.id)
        store.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnail.path))
    }

    func testDeduplicatingImageRemovesOnlyNewAssets() throws {
        let first = store.assetsDirectory.appendingPathComponent("first.png")
        let duplicate = store.assetsDirectory.appendingPathComponent("duplicate.png")
        try Data([1]).write(to: first)
        try Data([1]).write(to: duplicate)

        store.insert(makeImageEntry(fingerprint: ClipboardEntry.fingerprint(type: .image, data: Data([1])), original: first.path))
        store.insert(makeImageEntry(fingerprint: ClipboardEntry.fingerprint(type: .image, data: Data([1])), original: duplicate.path))
        store.flush()

        XCTAssertEqual(store.allEntries.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicate.path))
    }

    func testCopyingImagesWithLegacyFingerprintCollisionPreservesBothFilesAfterRestart() throws {
        let first = store.assetsDirectory.appendingPathComponent("first.png")
        let second = store.assetsDirectory.appendingPathComponent("second.png")
        try Data([65, 98]).write(to: first)
        try Data([66, 65]).write(to: second)
        store.insert(makeImageEntry(fingerprint: "legacy-collision", original: first.path))
        store.insert(makeImageEntry(fingerprint: "legacy-collision", original: second.path))
        store.flush()

        let reloaded = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        XCTAssertEqual(reloaded.allEntries.count, 2)
        XCTAssertEqual(try Data(contentsOf: first), Data([65, 98]))
        XCTAssertEqual(try Data(contentsOf: second), Data([66, 65]))
    }

    func testCorruptHistoryAndImagesRemainInPrivateRecoveryDirectoryAcrossRestarts() throws {
        let history = tempDir.appendingPathComponent("clipboard_history.json")
        let preserved = store.assetsDirectory.appendingPathComponent("preserved.png")
        try Data([1]).write(to: preserved)
        try Data("not json".utf8).write(to: history)

        let recovered = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        let files = try FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        )
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("clipboard_recovery_") })
        let backupHistory = backup.appendingPathComponent("clipboard_history.json")
        let backupImage = backup.appendingPathComponent("ClipboardAssets/preserved.png")
        recovered.insert(makeEntry(text: "new history"))
        recovered.flush()
        for _ in 0..<2 {
            let reloaded = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
            XCTAssertEqual(reloaded.allEntries.first?.plainText, "new history")
            reloaded.flush()
        }

        XCTAssertEqual(try Data(contentsOf: backupHistory), Data("not json".utf8))
        XCTAssertEqual(try Data(contentsOf: backupImage), Data([1]))
        XCTAssertEqual(try permissions(at: backup), 0o700)
        XCTAssertEqual(try permissions(at: backupHistory), 0o600)
        XCTAssertEqual(try permissions(at: backupImage), 0o600)
    }

    func testFailedImageBackupDoesNotOverwriteCorruptHistoryWhenSavingNewEntries() throws {
        let history = tempDir.appendingPathComponent("clipboard_history.json")
        let corruptData = Data("unrecoverable json".utf8)
        try corruptData.write(to: history)
        try FileManager.default.removeItem(at: store.assetsDirectory)
        try FileManager.default.createSymbolicLink(
            at: store.assetsDirectory, withDestinationURL: tempDir.appendingPathComponent("missing-assets")
        )

        let recovered = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        recovered.insert(makeEntry(text: "new entry"))
        recovered.flush()

        XCTAssertNotNil(recovered.lastError)
        XCTAssertEqual(try Data(contentsOf: history), corruptData)
    }

    func testLegacyCorruptBackupAndImagesAreProtectedBeforeStartupCleanup() throws {
        store.insert(makeEntry(text: "current history"))
        store.flush()
        let legacy = tempDir.appendingPathComponent("clipboard_history.corrupt-123.json")
        try Data("old corrupt history".utf8).write(to: legacy)
        let image = store.assetsDirectory.appendingPathComponent("legacy.png")
        try Data([7]).write(to: image)

        let migrated = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        migrated.flush()
        _ = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("clipboard_recovery_") })

        XCTAssertEqual(migrated.allEntries.first?.plainText, "current history")
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent(legacy.lastPathComponent)),
                       Data("old corrupt history".utf8))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("ClipboardAssets/legacy.png")), Data([7]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    // MARK: - Helpers

    private func makeEntry(text: String, type: ClipboardContentType = .text, fingerprint: String? = nil) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(),
            contentType: type,
            plainText: text,
            title: String(text.prefix(50)),
            subtitle: nil,
            createdAt: Date(),
            sourceAppBundleID: "com.test.app",
            sourceAppName: "TestApp",
            isPinned: false,
            lastUsedAt: nil,
            fingerprint: fingerprint ?? ClipboardEntry.fingerprint(type: type, content: text),
            imagePath: nil,
            thumbnailPath: nil,
            filePaths: nil,
            colorHex: nil
        )
    }

    private func makeImageEntry(
        fingerprint: String,
        original: String,
        thumbnail: String? = nil
    ) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), contentType: .image, plainText: nil, title: "Image",
            subtitle: nil, createdAt: Date(), sourceAppBundleID: nil,
            sourceAppName: nil, isPinned: false, lastUsedAt: nil,
            fingerprint: fingerprint, imagePath: original,
            thumbnailPath: thumbnail, filePaths: nil, colorHex: nil
        )
    }
}
