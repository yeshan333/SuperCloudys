import XCTest
@testable import SuperCloudys

final class AppInputSourceControllerTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let suiteName = "AppInputSourceTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: InputSourceSettings
        let service = TestInputSourceService()
        let indicator = TestInputSourceIndicator()
        var frontmost: String? = "test.editor"
        lazy var controller = AppInputSourceController(
            settings: settings, service: service, indicator: indicator,
            frontmostBundleID: { [weak self] in self?.frontmost }
        )

        init(enabled: Bool = true) {
            defaults = UserDefaults(suiteName: suiteName)!
            settings = InputSourceSettings(defaults: defaults)
            settings.isEnabled = enabled
            settings.rules = [AppInputSourceRule(
                bundleID: "test.editor", appName: "Editor", appPath: "/Applications/Editor.app",
                inputSource: service.english.id, inputSourceName: service.english.name
            )]
        }

        func cleanUp() {
            controller.stopMonitoring()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @MainActor
    func testNewSettingsStartWithAutomaticSwitchingDisabledAndNoRules() {
        let suite = "InputSourceDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InputSourceSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(settings.rules.isEmpty)
    }

    @MainActor
    func testEnteringConfiguredAppSelectsItsDefaultInputSource() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertEqual(fixture.service.selections, [fixture.service.english.id])
        XCTAssertNil(fixture.controller.lastError)
    }

    @MainActor
    func testEnteringUnconfiguredAppOrDisablingSwitchingPreservesCurrentInputSource() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.frontmost = "test.browser"
        fixture.controller.applyDefault(for: "test.browser")
        fixture.frontmost = "test.editor"
        fixture.controller.setEnabled(false)
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertTrue(fixture.service.selections.isEmpty)
        XCTAssertEqual(fixture.service.current, fixture.service.chinese.id)
    }

    @MainActor
    func testEnteringAppAlreadyUsingItsDefaultAvoidsReselectingInputSource() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.service.current = fixture.service.english.id
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertTrue(fixture.service.selections.isEmpty)
    }

    @MainActor
    func testReturningToConfiguredAppRestoresDefaultAfterManualInputSourceChange() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.applyDefault(for: "test.editor")
        fixture.service.current = fixture.service.chinese.id
        fixture.controller.refreshSources()
        XCTAssertEqual(fixture.service.current, fixture.service.chinese.id)
        XCTAssertEqual(fixture.service.selections.count, 1)
        fixture.frontmost = "test.browser"
        fixture.controller.applyDefault(for: "test.browser")
        fixture.frontmost = "test.editor"
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertEqual(fixture.service.selections, [fixture.service.english.id, fixture.service.english.id])
    }

    @MainActor
    func testUnavailableDefaultPreservesCurrentInputSourceAndRuleAndReportsError() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.service.sources = [fixture.service.chinese]
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertTrue(fixture.service.selections.isEmpty)
        XCTAssertEqual(fixture.controller.rules.count, 1)
        XCTAssertTrue(fixture.controller.lastError?.contains("不可用") == true)
        fixture.service.sources.append(fixture.service.english)
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertEqual(fixture.service.selections, [fixture.service.english.id])
        XCTAssertNil(fixture.controller.lastError)
    }

    @MainActor
    func testSystemSelectionFailureReportsErrorAndNextSuccessfulEntryClearsIt() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.service.selectionStatus = -50
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertTrue(fixture.controller.lastError?.contains("无法切换") == true)
        XCTAssertEqual(fixture.service.current, fixture.service.chinese.id)
        fixture.service.selectionStatus = 0
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertNil(fixture.controller.lastError)
        XCTAssertEqual(fixture.service.current, fixture.service.english.id)
    }

    @MainActor
    func testUpdatingRuleReplacesSameBundleIDAndRestartRestoresRuleAndEnabledState() {
        let fixture = Fixture(enabled: false)
        defer { fixture.cleanUp() }
        let mode = KeyboardInputSource(
            id: InputSourceIdentifier(sourceID: "test.ime", modeID: "traditional"), name: "繁体"
        )
        fixture.controller.setRule(
            bundleID: "test.editor", appName: "Moved Editor", appPath: "/Other/Editor.app", source: mode
        )
        XCTAssertEqual(fixture.controller.rules.count, 1)
        let restored = AppInputSourceController(
            settings: InputSourceSettings(defaults: fixture.defaults),
            service: fixture.service, frontmostBundleID: { nil }
        )
        XCTAssertEqual(restored.rules, fixture.controller.rules)
        XCTAssertEqual(restored.rules.first?.inputSource.modeID, "traditional")
        XCTAssertFalse(restored.isEnabled)
        fixture.controller.setEnabled(true)
        XCTAssertTrue(InputSourceSettings(defaults: fixture.defaults).isEnabled)
    }

    @MainActor
    func testRemovingRulePersistsRemovalAndStopsSwitchingForThatApp() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.removeRule(bundleID: "test.editor")
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertTrue(fixture.settings.rules.isEmpty)
        XCTAssertTrue(fixture.service.selections.isEmpty)
    }

    @MainActor
    func testInputModesSharingSourceIDSelectTheConfiguredMode() {
        let fixture = Fixture(enabled: false)
        defer { fixture.cleanUp() }
        let simplified = KeyboardInputSource(
            id: InputSourceIdentifier(sourceID: "test.ime", modeID: "simplified"), name: "简体"
        )
        let traditional = KeyboardInputSource(
            id: InputSourceIdentifier(sourceID: "test.ime", modeID: "traditional"), name: "繁体"
        )
        fixture.service.sources = [simplified, traditional]
        fixture.service.current = simplified.id
        fixture.controller.setRule(
            bundleID: "test.editor", appName: "Editor", appPath: "/Applications/Editor.app", source: traditional
        )
        fixture.controller.setEnabled(true)
        fixture.controller.applyDefault(for: "test.editor")
        XCTAssertEqual(fixture.service.selections, [traditional.id])
    }

    @MainActor
    func testDelayedSwitchDoesNotAffectAppThatIsNoLongerFrontmost() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.scheduleSwitch(for: "test.editor")
        fixture.frontmost = "test.browser"
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(fixture.service.selections.isEmpty)
    }

    @MainActor
    func testRapidAppSwitchCancelsEarlierRequestAndAppliesLatestAppDefault() async throws {
        let fixture = Fixture(enabled: false)
        defer { fixture.cleanUp() }
        fixture.controller.setRule(
            bundleID: "test.browser", appName: "Browser", appPath: "/Applications/Browser.app",
            source: fixture.service.chinese
        )
        fixture.service.current = nil
        let selected = expectation(description: "最新前台应用使用中文输入法")
        fixture.service.onSelect = { selected.fulfill() }
        fixture.controller.setEnabled(true)
        fixture.controller.scheduleSwitch(for: "test.editor")
        fixture.frontmost = "test.browser"
        fixture.controller.scheduleSwitch(for: "test.browser")
        await fulfillment(of: [selected], timeout: 2)
        XCTAssertEqual(fixture.service.selections, [fixture.service.chinese.id])
    }

    @MainActor
    func testDisablingOrStoppingMonitoringCancelsPendingSwitch() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.scheduleSwitch(for: "test.editor")
        fixture.controller.setEnabled(false)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(fixture.service.selections.isEmpty)
        fixture.controller.setEnabled(true)
        fixture.controller.stopMonitoring()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(fixture.service.selections.isEmpty)
    }

    @MainActor
    func testStartingMonitoringAppliesSavedDefaultToCurrentApp() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let selected = expectation(description: "启动后应用已保存的默认输入法")
        fixture.service.onSelect = { selected.fulfill() }
        fixture.controller.startMonitoring()
        fixture.controller.startMonitoring()
        await fulfillment(of: [selected], timeout: 2)
        XCTAssertEqual(fixture.service.selections, [fixture.service.english.id])
    }

    @MainActor
    func testSystemInputSourceListHasUniqueIdentitiesAndIncludesCurrentKeyboardSource() throws {
        let service = SystemInputSourceService()
        let sources = service.availableSources()
        XCTAssertFalse(sources.isEmpty)
        XCTAssertEqual(Set(sources.map(\.id)).count, sources.count)
        let current = try XCTUnwrap(service.currentSourceID())
        XCTAssertTrue(sources.contains { $0.id == current })
    }

    @MainActor
    func testEnteringConfiguredAppShowsActualInputSourceAfterApplyingDefault() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        let shown = expectation(description: "显示切换后的实际输入法")
        fixture.indicator.onShow = { shown.fulfill() }
        fixture.controller.scheduleSwitch(for: "test.editor")
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(fixture.indicator.contents.map(\.source), [fixture.service.english])
        XCTAssertEqual(fixture.indicator.contents.first?.appName, "Editor")
    }

    @MainActor
    func testEnteringUnconfiguredAppShowsCurrentInputSourceWithoutChangingIt() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.frontmost = "test.browser"
        let shown = expectation(description: "未配置应用显示当前输入法")
        fixture.indicator.onShow = { shown.fulfill() }
        fixture.controller.scheduleSwitch(for: "test.browser")
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(fixture.indicator.contents.map(\.source), [fixture.service.chinese])
        XCTAssertTrue(fixture.service.selections.isEmpty)
    }

    @MainActor
    func testFailedDefaultSelectionShowsActualInputSourceInsteadOfConfiguredDefault() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.service.selectionStatus = -50
        fixture.controller.applyDefault(for: "test.editor")
        fixture.controller.showCurrentInputSource(for: "test.editor")
        XCTAssertNotNil(fixture.controller.lastError)
        XCTAssertEqual(fixture.indicator.contents.map(\.source), [fixture.service.chinese])
    }

    @MainActor
    func testManualInputSourceChangeUpdatesPromptWithoutRestoringAppDefault() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.applyDefault(for: "test.editor")
        fixture.service.current = fixture.service.chinese.id
        let shown = expectation(description: "提示显示用户手动选择的输入法")
        fixture.indicator.onShow = { shown.fulfill() }
        fixture.controller.inputSourceDidChange()
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(fixture.indicator.contents.map(\.source), [fixture.service.chinese])
        XCTAssertEqual(fixture.service.selections, [fixture.service.english.id])
    }

    @MainActor
    func testTurningOffPromptsKeepsAutomaticSwitchingAndPersistsPromptSetting() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        XCTAssertTrue(fixture.controller.showsIndicator)
        fixture.controller.showCurrentInputSource(for: "test.editor")
        XCTAssertTrue(fixture.indicator.isVisible)
        fixture.controller.setShowsIndicator(false)
        XCTAssertFalse(fixture.indicator.isVisible)
        XCTAssertFalse(InputSourceSettings(defaults: fixture.defaults).showsIndicator)
        fixture.indicator.contents = []
        fixture.controller.scheduleSwitch(for: "test.editor")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(fixture.service.selections, [fixture.service.english.id])
        XCTAssertTrue(fixture.indicator.contents.isEmpty)
    }

    @MainActor
    func testDisablingAutomaticSwitchingStillShowsCurrentInputSourceOnAppEntry() async {
        let fixture = Fixture(enabled: false)
        defer { fixture.cleanUp() }
        let shown = expectation(description: "自动切换关闭后仍显示当前输入法")
        fixture.indicator.onShow = { shown.fulfill() }
        fixture.controller.scheduleSwitch(for: "test.editor")
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(fixture.indicator.contents.map(\.source), [fixture.service.chinese])
        XCTAssertTrue(fixture.service.selections.isEmpty)
    }

    @MainActor
    func testRapidAppChangesHidePreviousPromptAndOnlyShowLatestApp() async {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.showCurrentInputSource(for: "test.editor")
        fixture.indicator.contents = []
        fixture.controller.scheduleSwitch(for: "test.editor")
        XCTAssertFalse(fixture.indicator.isVisible)
        fixture.frontmost = "test.browser"
        fixture.controller.scheduleSwitch(for: "test.browser")
        let shown = expectation(description: "只显示最新前台应用的输入法提示")
        fixture.indicator.onShow = { shown.fulfill() }
        await fulfillment(of: [shown], timeout: 2)
        XCTAssertEqual(fixture.indicator.contents.map(\.bundleID), ["test.browser"])
        XCTAssertEqual(fixture.indicator.contents.map(\.source), [fixture.service.chinese])
    }

    @MainActor
    func testUnknownCurrentSourceHidesPromptInsteadOfGuessingFromDefault() {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.showCurrentInputSource(for: "test.editor")
        fixture.indicator.contents = []
        fixture.service.current = nil
        fixture.controller.showCurrentInputSource(for: "test.editor")
        XCTAssertFalse(fixture.indicator.isVisible)
        XCTAssertTrue(fixture.indicator.contents.isEmpty)
    }

    @MainActor
    func testStoppingMonitoringCancelsPendingPromptAndHidesVisiblePrompt() async throws {
        let fixture = Fixture()
        defer { fixture.cleanUp() }
        fixture.controller.showCurrentInputSource(for: "test.editor")
        fixture.indicator.contents = []
        fixture.controller.inputSourceDidChange()
        fixture.controller.stopMonitoring()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(fixture.indicator.isVisible)
        XCTAssertTrue(fixture.indicator.contents.isEmpty)
    }

    /// 手动运行的系统集成检查，常规测试不改变用户的输入法。
    @MainActor
    func testSystemSelectionChangesCurrentInputSourceAndRestoresOriginal() async throws {
        guard ProcessInfo.processInfo.environment["SUPERCLOUDYS_INPUT_SOURCE_SMOKE"] == "1" else {
            throw XCTSkip("设置 SUPERCLOUDYS_INPUT_SOURCE_SMOKE=1 才执行真实输入法切换检查")
        }
        let service = SystemInputSourceService()
        let original = try XCTUnwrap(service.currentSourceID())
        guard let target = service.availableSources().first(where: { $0.id != original }) else {
            throw XCTSkip("系统只启用了一个输入法")
        }
        defer {
            XCTAssertEqual(service.select(original), 0)
            XCTAssertEqual(service.currentSourceID(), original, "检查后应恢复原输入法")
        }
        XCTAssertEqual(service.select(target.id), 0)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.currentSourceID(), target.id)
    }
}

@MainActor
private final class TestInputSourceIndicator: InputSourceIndicatorPresenting {
    var contents: [InputSourceIndicatorContent] = []
    var isVisible = false
    var onShow: (() -> Void)?

    func show(_ content: InputSourceIndicatorContent) {
        contents.append(content)
        isVisible = true
        onShow?()
    }

    func hide() { isVisible = false }
}

@MainActor
private final class TestInputSourceService: InputSourceService {
    let english = KeyboardInputSource(id: InputSourceIdentifier(sourceID: "test.english", modeID: nil), name: "ABC")
    let chinese = KeyboardInputSource(id: InputSourceIdentifier(sourceID: "test.chinese", modeID: "pinyin"), name: "拼音")
    lazy var sources = [english, chinese]
    lazy var current: InputSourceIdentifier? = chinese.id
    var selections: [InputSourceIdentifier] = []
    var selectionStatus: Int32 = 0
    var onSelect: (() -> Void)?

    func availableSources() -> [KeyboardInputSource] { sources }
    func currentSourceID() -> InputSourceIdentifier? { current }
    func select(_ identifier: InputSourceIdentifier) -> Int32 {
        selections.append(identifier)
        if selectionStatus == 0 { current = identifier }
        onSelect?()
        return selectionStatus
    }
}
