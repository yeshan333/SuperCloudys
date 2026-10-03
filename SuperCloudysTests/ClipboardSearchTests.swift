import XCTest
@testable import SuperCloudys

final class ClipboardSearchTests: XCTestCase {
    func testFullTextSearchPreservesCaseInsensitiveChineseAndUnicodeMatches() {
        let cases: [(String, String)] = [
            ("Hello WORLD", "world"), ("剪贴板历史搜索", "历史"),
            ("剪贴板历史搜索", "板"), ("café", "cafe\u{301}"),
            ("cafe\u{301}", "CAFÉ"), ("Straße", "STRASSE"),
            ("Αθήνα", "αθήνα"), ("👩🏽‍💻 clipboard", "👩🏽‍💻"),
            ("café", "cafe"), ("clipboard", "missing"),
            (String(repeating: "x", count: 131_072) + "结尾 NEEDLE", "needle")
        ]
        for (text, query) in cases {
            let entry = makeEntry(text: text)
            let expected = text.range(of: query, options: .caseInsensitive) != nil
            XCTAssertEqual(ClipboardSearch.matches(entry, query: query), expected,
                           "匹配语义发生变化：\(query)")
        }
    }

    func testSearchMatchesTitleBodyAndSourceWithoutTreatingQueryAsPattern() {
        let title = makeEntry(text: "body", title: "TitleOnly")
        let source = makeEntry(text: nil, source: "SourceOnly")
        let body = makeEntry(text: "literal [a-z].* and %_")
        XCTAssertTrue(ClipboardSearch.matches(title, query: "titleonly"))
        XCTAssertTrue(ClipboardSearch.matches(source, query: "sourceonly"))
        XCTAssertTrue(ClipboardSearch.matches(body, query: "[a-z].*"))
        XCTAssertTrue(ClipboardSearch.matches(body, query: "%_"))
        XCTAssertFalse(ClipboardSearch.matches(source, query: "missing"))
        XCTAssertTrue(ClipboardSearch.matches(source, query: ""))
    }

    func testSearchDoesNotMatchInsideEmojiCombiningCharactersOrCRLF() {
        let cases: [(String, String)] = [
            ("👩🏽‍💻", "💻"), ("👩🏽‍💻", "🏽"), ("👩🏽‍💻", "👩🏽"),
            ("🇨🇳", "🇨"), ("a\u{301}", "\u{301}"),
            ("क्", "क"), ("क्🏽", "क्"), ("क\u{301}", "क"),
            ("\r\n", "\r"), ("\r\n", "\n")
        ]
        for (text, query) in cases {
            XCTAssertNil(text.range(of: query, options: .caseInsensitive))
            XCTAssertFalse(ClipboardSearch.matches(makeEntry(text: text), query: query),
                           "不应匹配字符簇内部：\(text.debugDescription), \(query.debugDescription)")
        }
    }

    func testSearchFindsLaterCompleteCharacterAfterAnEarlierPartialCharacterMatch() {
        let cases: [(String, String)] = [
            ("👩🏽‍💻 💻", "💻"), ("👩🏽‍💻 👩🏽", "👩🏽"),
            ("a\u{301}\n\u{301}", "\u{301}"),
            ("क् क", "क"), ("\r\n\r", "\r"), ("\r\n\n", "\n")
        ]
        for (text, query) in cases {
            XCTAssertNotNil(text.range(of: query, options: .caseInsensitive))
            XCTAssertTrue(ClipboardSearch.matches(makeEntry(text: text), query: query),
                          "应继续找到后面的完整字符：\(text.debugDescription), \(query.debugDescription)")
        }
    }

    func testSearchFindsLineBreakBeforeAStandaloneCombiningMark() {
        for text in ["a\n\u{301}", "a\n🏽"] {
            XCTAssertNotNil(text.range(of: "\n", options: .caseInsensitive))
            XCTAssertTrue(ClipboardSearch.matches(makeEntry(text: text), query: "\n"))
        }
    }

    func testTextFilterIncludesLegacyRichTextAndPreservesPinnedThenRecentlyUsedOrder() {
        let pinned = makeEntry(text: "match", pinned: true, time: 1)
        let rich = makeEntry(text: "match", type: .richText, time: 2, used: 10)
        let text = makeEntry(text: "match", time: 3)
        let url = makeEntry(text: "match", type: .url, time: 20)
        let sorted = ClipboardSearch.sorted([text, url, rich, pinned])
        XCTAssertEqual(ClipboardSearch.filter(sorted, query: "match", type: .text)?.map(\.id),
                       [pinned.id, rich.id, text.id])
        XCTAssertEqual(ClipboardSearch.filter(sorted, query: "match", type: .url)?.map(\.id),
                       [url.id])
    }

    func testCancelledSearchStopsBeforeScanningRemainingHistoryAndDiscardsPartialResults() {
        let entries = (0..<100).map { makeEntry(text: "entry \($0)") }
        var checks = 0
        let result = ClipboardSearch.filter(entries, query: "entry", isCancelled: {
            checks += 1
            return checks >= 3
        })
        XCTAssertNil(result)
        XCTAssertEqual(checks, 3)
    }

    func testCancellationBeforeSearchReturnsNoResultEvenForEmptyHistory() {
        XCTAssertNil(ClipboardSearch.filter([], query: "", isCancelled: { true }))
    }

    private func makeEntry(
        text: String?, title: String = "title", source: String? = nil,
        type: ClipboardContentType = .text, pinned: Bool = false,
        time: TimeInterval = 0, used: TimeInterval? = nil
    ) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), contentType: type, plainText: text, title: title,
            subtitle: nil, createdAt: Date(timeIntervalSince1970: time),
            sourceAppBundleID: nil, sourceAppName: source, isPinned: pinned,
            lastUsedAt: used.map { Date(timeIntervalSince1970: $0) },
            fingerprint: UUID().uuidString, imagePath: nil, thumbnailPath: nil,
            filePaths: nil, colorHex: nil
        )
    }
}
