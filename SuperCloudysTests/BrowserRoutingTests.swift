import XCTest
import AppKit
import Carbon
@testable import SuperCloudys

final class BrowserRoutingTests: XCTestCase {
    private let chrome = "com.google.Chrome"
    private let firefox = "org.mozilla.firefoxdeveloperedition"
    private let ownID = "com.yeshan333.SuperCloudys"

    func testInitialRulesSendEveryGitLabPathToFirefoxDeveloperEditionAndOtherSitesToChrome() {
        let config = BrowserRoutingConfiguration()
        for address in [
            "https://gitlab.lingxigames-inc.com/",
            "https://gitlab.lingxigames-inc.com/team/repo/-/merge_requests/42?tab=diff#note",
            "http://gitlab.lingxigames-inc.com/team/repo"
        ] {
            XCTAssertEqual(config.destinations(for: URL(string: address)!, availableBrowserIDs: [chrome, firefox], ownBundleID: ownID).first, firefox)
        }
        for address in ["https://example.com/", "https://sub.gitlab.lingxigames-inc.com/", "https://gitlab.lingxigames-inc.com.evil.test/"] {
            XCTAssertEqual(config.destinations(for: URL(string: address)!, availableBrowserIDs: [chrome, firefox], ownBundleID: ownID).first, chrome)
        }
    }

    func testDomainRuleIgnoresCasePortAndTrailingDotAndRespectsSubdomainBoundaries() {
        let rule = BrowserRoutingRule(pattern: " Example.COM. ")
        for address in ["https://EXAMPLE.com:8443/path", "http://example.com./", "https://a.b.example.com/"] {
            XCTAssertTrue(rule.matches(URL(string: address)!), address)
        }
        for address in ["https://badexample.com/", "https://example.com.evil.test/", "https://example.com@evil.test/", "https://evil.test/?host=example.com"] {
            XCTAssertFalse(rule.matches(URL(string: address)!), address)
        }
    }

    func testExactDomainRuleExcludesSubdomains() {
        let rule = BrowserRoutingRule(pattern: "example.com", includesSubdomains: false)
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/any/path")!))
        XCTAssertFalse(rule.matches(URL(string: "https://sub.example.com/")!))
    }

    func testPathPrefixRuleCanBeRestrictedToADomainAndExcludesQueryAndFragment() {
        let rule = BrowserRoutingRule(kind: .pathPrefix, pattern: "/projects/", domain: "example.com", includesSubdomains: false)
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/projects/42?view=diff#note")!))
        for address in ["https://other.test/projects/42", "https://example.com/Projects/42", "https://example.com/?next=/projects/42", "https://example.com/#/projects/42", "https://example.com/projects%2F42"] {
            XCTAssertFalse(rule.matches(URL(string: address)!), address)
        }
    }

    func testUnrestrictedPathPrefixMatchesAcrossDomainsWithLiteralPrefixSemantics() {
        let rule = BrowserRoutingRule(kind: .pathPrefix, pattern: "/docs")
        XCTAssertTrue(rule.matches(URL(string: "https://one.test/docs/page")!))
        XCTAssertTrue(rule.matches(URL(string: "https://two.test/docs-old")!))
        XCTAssertTrue(BrowserRoutingRule(kind: .pathPrefix, pattern: "/").matches(URL(string: "https://one.test")!))
    }

    func testRegularExpressionMatchesCompleteURLIncludingQueryAndFragment() {
        let rule = BrowserRoutingRule(kind: .regularExpression, pattern: #"^https://example\.com/repo/\d+\?view=diff#note$"#)
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/repo/42?view=diff#note")!))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com/repo/name?view=diff#note")!))
        XCTAssertFalse(rule.matches(URL(string: "http://example.com/repo/42?view=diff#note")!))
        let unicode = BrowserRoutingRule(kind: .regularExpression, pattern: "note$")
        XCTAssertTrue(unicode.matches(URL(string: "https://example.com/中文#note")!))
    }

    func testInvalidPatternsAndNonWebURLsNeverMatch() {
        for rule in [
            BrowserRoutingRule(pattern: ""), BrowserRoutingRule(pattern: "https://example.com/path"),
            BrowserRoutingRule(pattern: "*.example.com"), BrowserRoutingRule(kind: .pathPrefix, pattern: "docs"),
            BrowserRoutingRule(kind: .pathPrefix, pattern: "/docs?query"),
            BrowserRoutingRule(kind: .pathPrefix, pattern: "/docs", domain: "bad/path"),
            BrowserRoutingRule(kind: .regularExpression, pattern: "[")
        ] {
            XCTAssertNotNil(rule.validationError)
            XCTAssertFalse(rule.matches(URL(string: "https://example.com/docs")!))
        }
        let all = BrowserRoutingRule(kind: .regularExpression, pattern: ".*")
        for address in ["file:///tmp/a", "mailto:a@example.com", "supercloudys://open?app=/tmp/a", "https:///path"] {
            XCTAssertFalse(all.matches(URL(string: address)!), address)
        }
    }

    func testFirstEnabledMatchingRuleWinsAndPausingRulesUsesFallback() {
        var config = BrowserRoutingConfiguration(rules: [
            BrowserRoutingRule(isEnabled: false, pattern: "example.com", browserBundleID: "disabled"),
            BrowserRoutingRule(pattern: "example.com", browserBundleID: firefox),
            BrowserRoutingRule(kind: .pathPrefix, pattern: "/", browserBundleID: chrome)
        ])
        let url = URL(string: "https://example.com/")!
        XCTAssertEqual(config.destinations(for: url, availableBrowserIDs: [chrome, firefox], ownBundleID: ownID), [firefox, chrome])
        config.isEnabled = false
        XCTAssertEqual(config.destinations(for: url, availableBrowserIDs: [chrome, firefox], ownBundleID: ownID).first, chrome)
    }

    func testUnavailableRuleTargetUsesFallbackAndNeverRoutesBackToSuperCloudys() {
        var config = BrowserRoutingConfiguration(rules: [BrowserRoutingRule(pattern: "example.com", browserBundleID: "missing")])
        let url = URL(string: "https://example.com/")!
        XCTAssertEqual(config.destinations(for: url, availableBrowserIDs: [ownID, chrome], ownBundleID: ownID), [chrome])
        config.fallbackBrowserBundleID = ownID
        config.rules[0].browserBundleID = ownID
        XCTAssertEqual(config.destinations(for: url, availableBrowserIDs: [ownID, "com.apple.Safari", chrome], ownBundleID: ownID), ["com.apple.Safari", chrome])
        XCTAssertTrue(config.destinations(for: url, availableBrowserIDs: [ownID], ownBundleID: ownID).isEmpty)
    }

    @MainActor
    func testEditingReorderingDisablingAndDeletingRulesSurviveRelaunch() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let controller = fixture.controller
        let first = controller.configuration.rules[0]
        var rule = BrowserRoutingRule(kind: .pathPrefix, pattern: "/docs", domain: "example.com", includesSubdomains: false)
        XCTAssertTrue(controller.saveRule(rule))
        rule.pattern = "/projects/"
        rule.isEnabled = false
        XCTAssertTrue(controller.saveRule(rule))
        controller.moveRule(rule.id, offset: -1)
        controller.setFallbackBrowser(firefox)
        controller.setEnabled(false)
        let reloaded = BrowserRoutingController(defaults: fixture.defaults, workspace: fixture.workspace)
        XCTAssertEqual(reloaded.configuration, controller.configuration)
        XCTAssertEqual(reloaded.configuration.rules.map(\.id), [rule.id, first.id])
        controller.removeRule(first.id)
        XCTAssertEqual(BrowserRoutingController(defaults: fixture.defaults, workspace: fixture.workspace).configuration.rules, [rule])
    }

    @MainActor
    func testBrowserChoicesExcludeSuperCloudysEvenWhenTheSystemListsItAsAWebHandler() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.workspace.browsers.append(InstalledBrowser(
            id: ownID, name: "SuperCloudys", url: URL(fileURLWithPath: "/Applications/SuperCloudys.app")
        ))
        XCTAssertEqual(fixture.controller.browsers.map(\.id), [chrome, firefox])
        fixture.controller.refreshBrowsers()
        XCTAssertEqual(fixture.controller.browsers.map(\.id), [chrome, firefox])
    }

    @MainActor
    func testSavedSuperCloudysTargetsAreReplacedWithChromeOrTheSelectedFallback() throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        for (savedFallback, expectedFallback) in [(ownID, chrome), (firefox, firefox)] {
            let saved = BrowserRoutingConfiguration(
                fallbackBrowserBundleID: savedFallback,
                rules: [BrowserRoutingRule(pattern: "example.com", browserBundleID: ownID)]
            )
            fixture.defaults.set(try JSONEncoder().encode(saved), forKey: BrowserRoutingController.settingsKey)
            let controller = BrowserRoutingController(defaults: fixture.defaults, workspace: fixture.workspace)
            XCTAssertEqual(controller.configuration.fallbackBrowserBundleID, expectedFallback)
            XCTAssertEqual(controller.configuration.rules[0].browserBundleID, expectedFallback)
            XCTAssertEqual(controller.configuration.rules[0].id, saved.rules[0].id)
            XCTAssertTrue(controller.preview(URL(string: "https://example.com/")!).contains(
                expectedFallback == chrome ? "Chrome" : "Firefox Developer Edition"
            ))
        }
    }

    @MainActor
    func testInvalidRuleAndSelfBrowserCannotReplaceSavedConfiguration() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let original = fixture.controller.configuration
        XCTAssertFalse(fixture.controller.saveRule(BrowserRoutingRule(kind: .regularExpression, pattern: "[")))
        XCTAssertFalse(fixture.controller.saveRule(BrowserRoutingRule(pattern: "example.com", browserBundleID: ownID)))
        fixture.controller.setFallbackBrowser(ownID)
        XCTAssertEqual(fixture.controller.configuration, original)
    }

    @MainActor
    func testCorruptSavedRulesRemainUntouchedAndShowRecoveryMessage() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let corrupt = Data("broken".utf8)
        fixture.defaults.set(corrupt, forKey: BrowserRoutingController.settingsKey)
        let controller = BrowserRoutingController(defaults: fixture.defaults, workspace: fixture.workspace)
        XCTAssertNotNil(controller.lastError)
        XCTAssertEqual(controller.configuration.fallbackBrowserBundleID, chrome)
        XCTAssertEqual(fixture.defaults.data(forKey: BrowserRoutingController.settingsKey), corrupt)
    }

    @MainActor
    func testOpeningGitLabUsesFirefoxAndPreservesOriginalQueryAndFragment() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let url = URL(string: "https://gitlab.lingxigames-inc.com/team/repo?next=a%2Fb#diff")!
        await fixture.controller.open(url)
        XCTAssertEqual(fixture.workspace.attempts.map(\.browser), [firefox])
        XCTAssertEqual(fixture.workspace.attempts.map(\.url), [url])
        XCTAssertNil(fixture.controller.lastError)
    }

    @MainActor
    func testLocalHTMLFilesUseFallbackBrowserAndIgnoreWebRulesEvenWhenRulesArePaused() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        XCTAssertTrue(fixture.controller.saveRule(BrowserRoutingRule(
            kind: .regularExpression, pattern: ".*", browserBundleID: firefox
        )))
        for enabled in [true, false] {
            fixture.controller.setEnabled(enabled)
            for ext in ["html", "htm", "xhtml", "HTML"] {
                let url = URL(fileURLWithPath: "/tmp/网页 preview.\(ext)")
                await fixture.controller.open(url)
                XCTAssertEqual(fixture.workspace.attempts.last?.browser, chrome)
                XCTAssertEqual(fixture.workspace.attempts.last?.url, url)
                XCTAssertNil(fixture.controller.lastError)
            }
        }
        XCTAssertEqual(fixture.workspace.attempts.count, 8)
    }

    @MainActor
    func testLocalHTMLUsesSelectedFallbackAndRetriesAnotherBrowserIfItFails() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.setFallbackBrowser(firefox)
        fixture.workspace.failingBrowsers = [firefox]
        let url = URL(string: "file:///tmp/example.html?mode=preview#section")!
        await fixture.controller.open(url)
        XCTAssertEqual(fixture.workspace.attempts.map(\.browser), [firefox, chrome])
        XCTAssertEqual(fixture.workspace.attempts.map(\.url), [url, url])
        XCTAssertNil(fixture.controller.lastError)
    }

    @MainActor
    func testOpeningNonHTMLLocalFilesDoesNotLaunchABrowser() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        for path in ["/tmp/readme.txt", "/tmp/image.png", "/tmp/program.app", "/tmp/folder.html/"] {
            await fixture.controller.open(URL(fileURLWithPath: path))
        }
        XCTAssertTrue(fixture.workspace.attempts.isEmpty)
    }

    @MainActor
    func testFinderOpenDocumentsEventForwardsEveryHTMLFileToChrome() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let opened = expectation(description: "Finder 交给应用的两个 HTML 文件均已转发")
        opened.expectedFulfillmentCount = 2
        fixture.workspace.onOpen = { opened.fulfill() }
        let delegate = AppDelegate()
        delegate.browserRoutingController = fixture.controller
        let urls = [URL(fileURLWithPath: "/tmp/first.html"), URL(fileURLWithPath: "/tmp/第二个文件.htm")]
        let documents = NSAppleEventDescriptor.list()
        for (index, url) in urls.enumerated() {
            documents.insert(NSAppleEventDescriptor(fileURL: url), at: index + 1)
        }
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(documents, forKeyword: AEKeyword(keyDirectObject))
        delegate.handleOpenDocumentsEvent(event, withReplyEvent: NSAppleEventDescriptor.null())
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertEqual(Set(fixture.workspace.attempts.map(\.url)), Set(urls))
        XCTAssertEqual(fixture.workspace.attempts.map(\.browser), [chrome, chrome])
    }

    @MainActor
    func testFirefoxLaunchFailureRetriesChromeWithoutUsingSystemDefaultHandler() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.workspace.failingBrowsers = [firefox]
        await fixture.controller.open(URL(string: "https://gitlab.lingxigames-inc.com/")!)
        XCTAssertEqual(fixture.workspace.attempts.map(\.browser), [firefox, chrome])
        XCTAssertNil(fixture.controller.lastError)
    }

    @MainActor
    func testRemovedFirefoxFallsBackToChromeAndAllLaunchFailuresAreReported() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.workspace.browsers.removeAll { $0.id == firefox }
        fixture.workspace.failingBrowsers = [chrome]
        await fixture.controller.open(URL(string: "https://gitlab.lingxigames-inc.com/")!)
        XCTAssertEqual(fixture.workspace.attempts.map(\.browser), [chrome])
        XCTAssertNotNil(fixture.controller.lastError)
    }

    @MainActor
    func testNoAvailableBrowsersReportsErrorAndUnsupportedSchemesDoNotLaunchApps() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        await fixture.controller.open(URL(string: "supercloudys://open?app=/tmp/a")!)
        XCTAssertTrue(fixture.workspace.attempts.isEmpty)
        XCTAssertNil(fixture.controller.lastError)
        fixture.workspace.browsers = []
        await fixture.controller.open(URL(string: "https://example.com/")!)
        XCTAssertNotNil(fixture.controller.lastError)
        XCTAssertTrue(fixture.workspace.attempts.isEmpty)
    }

    @MainActor
    func testSettingDefaultRegistersBothWebSchemesAndKeepsChromeAsFallbackAfterRelaunch() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        await fixture.controller.makeDefaultBrowser()
        XCTAssertEqual(fixture.workspace.defaultRequests, ["http", "https"])
        XCTAssertTrue(fixture.controller.isDefaultBrowser)
        XCTAssertFalse(fixture.controller.isSettingDefault)
        XCTAssertEqual(BrowserRoutingController(defaults: fixture.defaults, workspace: fixture.workspace).configuration.fallbackBrowserBundleID, chrome)
        await fixture.controller.makeDefaultBrowser()
        XCTAssertEqual(fixture.workspace.defaultRequests, ["http", "https"])
    }

    @MainActor
    func testDeclinedDefaultBrowserChangeReportsPartialStateAndCanBeRetried() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.workspace.failingScheme = "https"
        await fixture.controller.makeDefaultBrowser()
        XCTAssertFalse(fixture.controller.isDefaultBrowser)
        XCTAssertFalse(fixture.controller.isSettingDefault)
        XCTAssertNotNil(fixture.controller.lastError)
        fixture.workspace.failingScheme = nil
        await fixture.controller.makeDefaultBrowser()
        XCTAssertEqual(fixture.workspace.defaultRequests, ["http", "https", "https"])
        XCTAssertTrue(fixture.controller.isDefaultBrowser)
        XCTAssertNil(fixture.controller.lastError)
    }

    @MainActor
    func testLinkPreviewShowsChosenBrowserWithoutLaunchingApplications() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        XCTAssertTrue(fixture.controller.preview(URL(string: "https://gitlab.lingxigames-inc.com/")!).contains("Firefox Developer Edition"))
        XCTAssertTrue(fixture.controller.preview(URL(string: "https://example.com/")!).contains("Chrome"))
        fixture.controller.setEnabled(false)
        XCTAssertTrue(fixture.controller.preview(URL(string: "https://gitlab.lingxigames-inc.com/")!).contains("Chrome"))
        XCTAssertTrue(fixture.workspace.attempts.isEmpty)
    }

    @MainActor
    private final class Fixture {
        let suite = "BrowserRoutingTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let workspace = TestBrowserWorkspace()
        lazy var controller = BrowserRoutingController(defaults: defaults, workspace: workspace)

        init() { defaults = UserDefaults(suiteName: suite)! }
        func cleanUp() { defaults.removePersistentDomain(forName: suite) }
    }
}

@MainActor
private final class TestBrowserWorkspace: BrowserWorkspace {
    var browsers = [
        InstalledBrowser(id: "com.google.Chrome", name: "Chrome", url: URL(fileURLWithPath: "/Applications/Google Chrome.app")),
        InstalledBrowser(id: "org.mozilla.firefoxdeveloperedition", name: "Firefox Developer Edition", url: URL(fileURLWithPath: "/Applications/Firefox Developer Edition.app"))
    ]
    var defaults = ["http": "com.google.Chrome", "https": "com.google.Chrome"]
    var attempts: [(url: URL, browser: String)] = []
    var failingBrowsers = Set<String>()
    var defaultRequests: [String] = []
    var failingScheme: String?
    var onOpen: (() -> Void)?

    func installedBrowsers() -> [InstalledBrowser] { browsers }
    func defaultBrowserID(for scheme: String) -> String? { defaults[scheme] }
    func setDefaultBrowser(for scheme: String) async throws {
        defaultRequests.append(scheme)
        if failingScheme == scheme { throw CocoaError(.userCancelled) }
        defaults[scheme] = BrowserRoutingController.ownBundleID
    }
    func open(_ url: URL, in browser: InstalledBrowser) async throws {
        attempts.append((url, browser.id))
        onOpen?()
        if failingBrowsers.contains(browser.id) { throw CocoaError(.fileNoSuchFile) }
    }
}
