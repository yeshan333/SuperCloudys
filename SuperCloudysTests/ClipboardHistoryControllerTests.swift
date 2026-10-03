import AppKit
import Combine
import XCTest
@testable import SuperCloudys

final class ClipboardHistoryControllerTests: XCTestCase {

    @MainActor
    func testHiddenPanelDefersSearchAndOpeningUsesLatestQuery() async throws {
        try await withSearchFixture { controller, _, entries in
            controller.searchQuery = "alpha"
            XCTAssertTrue(controller.filteredEntries.isEmpty)
            controller.searchQuery = "beta"
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[1].id])
        }
    }

    @MainActor
    func testNewQueryReplacesPendingSearchAndClearingRestoresAllEntries() async throws {
        try await withSearchFixture { controller, _, entries in
            controller.isPanelVisible = true
            controller.searchQuery = "alpha"
            controller.searchQuery = "beta"
            await waitForEntries(controller, ids: [entries[1].id])
            controller.clearSearch()
            await waitForEntries(controller, ids: [entries[1].id, entries[0].id])
        }
    }

    @MainActor
    func testClosingPanelCancelsPendingSearchAndReopeningAppliesIt() async throws {
        try await withSearchFixture { controller, _, entries in
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[1].id, entries[0].id])
            controller.searchQuery = "alpha"
            controller.isPanelVisible = false
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(controller.filteredEntries.map(\.id), [entries[1].id, entries[0].id])
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[0].id])
        }
    }

    @MainActor
    func testPinAndDeleteInvalidateCachedOrderAndHiddenChangesAppearOnReopen() async throws {
        try await withSearchFixture { controller, _, entries in
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[1].id, entries[0].id])
            controller.togglePin(id: entries[0].id)
            await waitForEntries(controller, ids: [entries[0].id, entries[1].id])
            controller.isPanelVisible = false
            controller.delete(id: entries[1].id)
            XCTAssertTrue(controller.filteredEntries.isEmpty)
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[0].id])
        }
    }

    @MainActor
    func testNewQueryCancelsSearchAlreadyScanningAndOnlyPublishesLatestMatches() async throws {
        let started = expectation(description: "旧查询已开始扫描")
        let stopped = expectation(description: "旧查询收到取消并停止")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        try await withSearchFixture(searchFilter: { entries, query, type in
            if query == "alpha" {
                started.fulfill()
                _ = release.wait(timeout: .now() + 5)
                XCTAssertTrue(Task.isCancelled)
                let result = ClipboardHistoryController.runSearch(entries, query: query, type: type)
                XCTAssertNil(result)
                stopped.fulfill()
                return result
            }
            return ClipboardHistoryController.runSearch(entries, query: query, type: type)
        }) { controller, _, entries in
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[1].id, entries[0].id])
            var publications: [[UUID]] = []
            let subscription = controller.$filteredEntries.dropFirst().sink {
                publications.append($0.map(\.id))
            }
            controller.searchQuery = "alpha"
            await fulfillment(of: [started], timeout: 2)
            controller.searchQuery = "beta"
            release.signal()
            await fulfillment(of: [stopped], timeout: 2)
            await waitForEntries(controller, ids: [entries[1].id])
            XCTAssertEqual(publications, [[entries[1].id]])
            withExtendedLifetime(subscription) {}
        }
    }

    @MainActor
    func testClosingPanelStopsSearchAlreadyScanningAndReopeningUsesLatestQuery() async throws {
        let started = expectation(description: "关闭前查询已开始扫描")
        let stopped = expectation(description: "关闭后正在扫描的查询停止")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        try await withSearchFixture(searchFilter: { entries, query, type in
            if query == "alpha" {
                started.fulfill()
                _ = release.wait(timeout: .now() + 5)
                XCTAssertTrue(Task.isCancelled)
                let result = ClipboardHistoryController.runSearch(entries, query: query, type: type)
                XCTAssertNil(result)
                stopped.fulfill()
                return result
            }
            return ClipboardHistoryController.runSearch(entries, query: query, type: type)
        }) { controller, _, entries in
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[1].id, entries[0].id])
            var publications: [[UUID]] = []
            let subscription = controller.$filteredEntries.dropFirst().sink {
                publications.append($0.map(\.id))
            }
            controller.searchQuery = "alpha"
            await fulfillment(of: [started], timeout: 2)
            controller.isPanelVisible = false
            release.signal()
            await fulfillment(of: [stopped], timeout: 2)
            XCTAssertEqual(controller.filteredEntries.map(\.id), [entries[1].id, entries[0].id])
            controller.searchQuery = "beta"
            controller.isPanelVisible = true
            await waitForEntries(controller, ids: [entries[1].id])
            XCTAssertFalse(publications.contains([entries[0].id]))
            withExtendedLifetime(subscription) {}
        }
    }

    @MainActor
    func testReopeningPanelDuringImageReadCancelsOldPasteWithoutWritingOrActivating() async throws {
        try await withSearchFixture { controller, _, _ in
            let started = expectation(description: "图片读取已挂起")
            let gate = PasteGate()
            var clipboardWrites = 0
            var activations = 0
            let task = Task { @MainActor in
                await controller.performPaste(copy: { isCurrent in
                    started.fulfill()
                    await gate.wait()
                    guard isCurrent() else { return false }
                    clipboardWrites += 1
                    return true
                }, paste: { _ in
                    activations += 1
                    return true
                })
            }
            await fulfillment(of: [started], timeout: 2)
            controller.isPanelVisible = true
            gate.resume()
            let result = await task.value
            XCTAssertEqual(result, .cancelled)
            XCTAssertEqual(clipboardWrites, 0)
            XCTAssertEqual(activations, 0)
        }
    }

    @MainActor
    func testReopeningPanelWhileTargetActivatesCancelsOldPasteBeforeKeyboardEvent() async throws {
        try await withSearchFixture { controller, _, _ in
            let started = expectation(description: "目标应用正在激活")
            let gate = PasteGate()
            var keyboardEvents = 0
            let task = Task { @MainActor in
                await controller.performPaste(copy: { _ in true }, paste: { isCurrent in
                    started.fulfill()
                    await gate.wait()
                    guard isCurrent() else { return false }
                    keyboardEvents += 1
                    return true
                })
            }
            await fulfillment(of: [started], timeout: 2)
            controller.rememberFrontmostApp()
            gate.resume()
            let result = await task.value
            XCTAssertEqual(result, .cancelled)
            XCTAssertEqual(keyboardEvents, 0)
        }
    }

    @MainActor
    func testNewPasteSupersedesPendingPasteAndOnlyNewRequestReachesDestination() async throws {
        try await withSearchFixture { controller, _, _ in
            let started = expectation(description: "第一个粘贴请求已挂起")
            let gate = PasteGate()
            var destinations: [String] = []
            let first = Task { @MainActor in
                await controller.performPaste(copy: { _ in
                    started.fulfill()
                    await gate.wait()
                    return true
                }, paste: { _ in
                    destinations.append("old")
                    return true
                })
            }
            await fulfillment(of: [started], timeout: 2)
            let latest = await controller.performPaste(copy: { _ in true }, paste: { _ in
                destinations.append("latest")
                return true
            })
            gate.resume()
            let original = await first.value
            XCTAssertEqual(latest, .pasted)
            XCTAssertEqual(original, .cancelled)
            XCTAssertEqual(destinations, ["latest"])
        }
    }

    @MainActor
    func testPasteCopyFailureReportsFailureWithoutActivatingDestination() async throws {
        try await withSearchFixture { controller, _, _ in
            var activated = false
            let result = await controller.performPaste(copy: { _ in false }, paste: { _ in
                activated = true
                return true
            })
            XCTAssertEqual(result, .failed)
            XCTAssertFalse(activated)
        }
    }

    @MainActor
    private final class PasteGate {
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private func waitForEntries(_ controller: ClipboardHistoryController, ids: [UUID]) async {
        let ready = expectation(description: "显示最新查询及排序结果")
        let subscription = controller.$filteredEntries
            .filter { $0.map(\.id) == ids }
            .first()
            .sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 2)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    private func withSearchFixture(
        searchFilter: @escaping ClipboardHistoryController.SearchFilter = { @Sendable entries, query, type in
            ClipboardHistoryController.runSearch(entries, query: query, type: type)
        },
        _ body: @MainActor (ClipboardHistoryController, ClipboardStore, [ClipboardEntry]) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardSearchTests_\(UUID().uuidString)")
        let suite = "ClipboardSearchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = ClipboardSettings(defaults: defaults)
        let store = ClipboardStore(storageDirectory: directory)
        let entries = ["alpha", "beta"].enumerated().map { index, text in
            ClipboardEntry(
                id: UUID(), contentType: .text, plainText: text, title: text,
                subtitle: nil, createdAt: Date().addingTimeInterval(Double(index)),
                sourceAppBundleID: nil, sourceAppName: nil, isPinned: false,
                lastUsedAt: nil, fingerprint: text, imagePath: nil, thumbnailPath: nil,
                filePaths: nil, colorHex: nil
            )
        }
        entries.forEach(store.insert)
        let monitor = ClipboardMonitorService(settings: settings)
        let controller = ClipboardHistoryController(
            store: store, monitor: monitor, settings: settings, searchFilter: searchFilter
        )
        defer {
            controller.isPanelVisible = false
            store.flush()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await body(controller, store, entries)
    }

    @MainActor
    func testCopyImagePathWhenFileExistsWritesFullPathAsTextAndMarksEntryUsed() throws {
        try withImagePathFixture { controller, store, pasteboard, directory in
            let path = directory.appendingPathComponent("图片 with spaces.png").path
            try Data([1, 2, 3]).write(to: URL(fileURLWithPath: path))
            let entry = imageEntry(path: path)
            store.insert(entry)

            XCTAssertTrue(controller.copyImagePathToClipboard(entry, pasteboard: pasteboard))
            XCTAssertEqual(pasteboard.string(forType: .string), path)
            XCTAssertNil(pasteboard.data(forType: .png))
            XCTAssertNotNil(store.allEntries.first?.lastUsedAt)
        }
    }

    @MainActor
    func testCopyImagePathWhenFileIsUnavailablePreservesClipboardAndUsage() throws {
        try withImagePathFixture { controller, store, pasteboard, directory in
            pasteboard.setString("已有剪贴板内容", forType: .string)
            let originalChangeCount = pasteboard.changeCount
            for path in [nil, "", directory.appendingPathComponent("missing.png").path, directory.path] {
                let entry = imageEntry(path: path)
                store.insert(entry)

                XCTAssertFalse(controller.copyImagePathToClipboard(entry, pasteboard: pasteboard))
                XCTAssertEqual(pasteboard.string(forType: .string), "已有剪贴板内容")
                XCTAssertEqual(pasteboard.changeCount, originalChangeCount)
                XCTAssertNil(store.allEntries.first?.lastUsedAt)
            }
        }
    }

    @MainActor
    private func withImagePathFixture(
        _ body: (ClipboardHistoryController, ClipboardStore, NSPasteboard, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardImagePathTests_\(UUID().uuidString)")
        let suiteName = "ClipboardImagePathTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = ClipboardSettings(defaults: defaults)
        let store = ClipboardStore(storageDirectory: directory)
        let monitor = ClipboardMonitorService(settings: settings)
        let controller = ClipboardHistoryController(store: store, monitor: monitor, settings: settings)
        let pasteboard = NSPasteboard.withUniqueName()
        defer {
            monitor.stop()
            store.flush()
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(controller, store, pasteboard, directory)
    }

    private func imageEntry(path: String?) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), contentType: .image, plainText: nil,
            title: "图片", subtitle: nil, createdAt: Date(),
            sourceAppBundleID: nil, sourceAppName: nil,
            isPinned: false, lastUsedAt: nil, fingerprint: UUID().uuidString,
            imagePath: path, thumbnailPath: nil, filePaths: nil, colorHex: nil
        )
    }

    @MainActor
    func testReturnCopiesUnlessCommandIsHeld() {
        XCTAssertEqual(ClipboardHistoryView.returnAction(for: []), .copy)
        XCTAssertEqual(ClipboardHistoryView.returnAction(for: [.command]), .paste)
    }

    @MainActor
    func testCycleTypeFilterWrapsForwardAndBackward() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryControllerTests_\(UUID().uuidString)")
        let suiteName = "ClipboardHistoryControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = ClipboardSettings(defaults: defaults)
        let store = ClipboardStore(maxEntries: 10, storageDirectory: tempDir)
        let monitor = ClipboardMonitorService(settings: settings)
        let controller = ClipboardHistoryController(
            store: store, monitor: monitor, settings: settings
        )
        defer {
            monitor.stop()
            store.flush()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        XCTAssertNil(controller.typeFilter)

        controller.cycleTypeFilter()
        XCTAssertEqual(controller.typeFilter, .text)

        for _ in ClipboardContentType.filterCases.dropFirst() {
            controller.cycleTypeFilter()
        }
        XCTAssertEqual(controller.typeFilter, .color)

        controller.cycleTypeFilter()
        XCTAssertNil(controller.typeFilter)

        controller.cycleTypeFilter(reverse: true)
        XCTAssertEqual(controller.typeFilter, .color)
    }
}
