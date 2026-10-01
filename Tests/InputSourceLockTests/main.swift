import Foundation
import InputSourceLockCore

final class MockTISService: TISServiceProtocol, @unchecked Sendable {
    var availableSources: [InputSourceInfo]
    var currentSource: InputSourceInfo?
    var selectedSourceID: String?

    init(available: [InputSourceInfo] = [], current: InputSourceInfo? = nil) {
        self.availableSources = available
        self.currentSource = current
    }

    func getKeyboardInputSources(includeAllInstalled: Bool) -> [InputSourceInfo] {
        return availableSources
    }

    func getCurrentKeyboardInputSource() -> InputSourceInfo? {
        return currentSource
    }

    func selectInputSource(id: String) -> Bool {
        selectedSourceID = id
        if let match = availableSources.first(where: { $0.id == id }) {
            currentSource = match
        }
        return true
    }
}

@MainActor
final class MockNotificationListener: NotificationListenerProtocol {
    weak var delegate: NotificationListenerDelegate?
    var isListening: Bool = false

    func startListening() {
        isListening = true
    }

    func stopListening() {
        isListening = false
    }
}

@MainActor
final class TestRunner {
    private var totalTests = 0
    private var passedTests = 0
    private var failedTests = 0

    func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) {
        if actual != expected {
            print("  ❌ [FAIL] \(file):\(line): Expected '\(expected)', but got '\(actual)'. \(message)")
            failedTests += 1
        } else {
            passedTests += 1
        }
    }

    func assertTrue(_ condition: Bool, _ message: String = "", file: String = #fileID, line: Int = #line) {
        if !condition {
            print("  ❌ [FAIL] \(file):\(line): Condition is false. \(message)")
            failedTests += 1
        } else {
            passedTests += 1
        }
    }

    func assertFalse(_ condition: Bool, _ message: String = "", file: String = #fileID, line: Int = #line) {
        if condition {
            print("  ❌ [FAIL] \(file):\(line): Condition is true. \(message)")
            failedTests += 1
        } else {
            passedTests += 1
        }
    }

    func assertNil<T>(_ value: T?, _ message: String = "", file: String = #fileID, line: Int = #line) {
        if value != nil {
            print("  ❌ [FAIL] \(file):\(line): Expected nil, but got '\(value!)'. \(message)")
            failedTests += 1
        } else {
            passedTests += 1
        }
    }

    func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #fileID, line: Int = #line) {
        if value == nil {
            print("  ❌ [FAIL] \(file):\(line): Expected non-nil value. \(message)")
            failedTests += 1
        } else {
            passedTests += 1
        }
    }

    func runTest(_ name: String, block: () -> Void) {
        totalTests += 1
        print("\n▶ Running test: \(name)...")
        let initialFails = failedTests
        block()
        if failedTests == initialFails {
            print("  ✅ [PASS] \(name)")
        }
    }

    private func makeSource(
        id: String,
        name: String,
        bundleID: String,
        selectable: Bool = true,
        enabled: Bool = true
    ) -> InputSourceInfo {
        return InputSourceInfo(
            id: id,
            name: name,
            bundleID: bundleID,
            isSelectCapable: selectable,
            isEnabled: enabled
        )
    }

    func runAll() {
        print("==================================================")
        print("  InputSourceLock Pure Logic & Throttling Test Suite")
        print("==================================================")

        runTest("菜单栏字母标识") {
            assertEqual(InputSourceMonogram.letter(name: "微信输入法", id: "com.tencent.inputmethod.wetype.pinyin"), "W")
            assertEqual(InputSourceMonogram.letter(name: "豆包输入法", id: "com.example.doubao"), "D")
            assertEqual(InputSourceMonogram.letter(name: "ABC", id: "com.apple.keylayout.ABC"), "A")
            assertEqual(InputSourceMonogram.letter(name: "搜狗拼音", id: "com.example.sogou"), "S")
            assertEqual(InputSourceMonogram.letter(name: nil, id: "com.tencent.inputmethod.wetype.pinyin"), "W")
            assertEqual(InputSourceMonogram.letter(name: nil, id: nil), "?")
        }

        // 1. Apple 布局同 bundle 不误并
        runTest("Apple 布局同 bundle 不误并") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let british = makeSource(id: "com.apple.keylayout.British", name: "British", bundleID: "com.apple.keyboardlayout.all")
            let us = makeSource(id: "com.apple.keylayout.US", name: "U.S.", bundleID: "com.apple.keyboardlayout.all")
            let sources = [british, us]

            engine.setPrimary(id: british.id)
            _ = engine.setLocked(true)

            // Switching to US which has the same bundle ID "com.apple.keyboardlayout.all"
            let action = engine.handleSelectedSourceChanged(newSourceID: us.id, availableSources: sources)

            // Must NOT allow US, must restore British
            assertEqual(action, .selectSource(targetID: british.id), "Should restore British when US is selected")
            assertFalse(engine.state.allowedIDs.contains(us.id), "US should not be in allowedIDs")
        }

        // 2. SCIM 同 bundle 不误并
        runTest("SCIM 同 bundle 不误并") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let itabc = makeSource(id: "com.apple.inputmethod.SCIM.ITABC", name: "Pinyin - Simplified", bundleID: "com.apple.inputmethod.SCIM")
            let wbx = makeSource(id: "com.apple.inputmethod.SCIM.WBX", name: "Wubi - Simplified", bundleID: "com.apple.inputmethod.SCIM")
            let shuangpin = makeSource(id: "com.apple.inputmethod.SCIM.Shuangpin", name: "Shuangpin - Simplified", bundleID: "com.apple.inputmethod.SCIM")
            let sources = [itabc, wbx, shuangpin]

            engine.setPrimary(id: itabc.id)
            _ = engine.setLocked(true)

            // Switched to WBX under the exact same bundle ID
            let action = engine.handleSelectedSourceChanged(newSourceID: wbx.id, availableSources: sources)

            // Must restore ITABC
            assertEqual(action, .selectSource(targetID: itabc.id), "Should restore ITABC when WBX is selected")
            assertEqual(engine.state.allowedIDs, [itabc.id], "Allowed IDs must strictly contain only ITABC")
        }

        // 3. WeType 单来源
        runTest("WeType 单来源") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let wetypePinyin = makeSource(id: "com.tencent.inputmethod.wetype.pinyin", name: "微信输入法", bundleID: "com.tencent.inputmethod.wetype", selectable: true, enabled: true)
            let wetypeDisabledMode = makeSource(id: "com.tencent.inputmethod.wetype", name: "微信输入法", bundleID: "com.tencent.inputmethod.wetype", selectable: false, enabled: true)
            let us = makeSource(id: "com.apple.keylayout.US", name: "U.S.", bundleID: "com.apple.keyboardlayout.all")
            let sources = [wetypePinyin, wetypeDisabledMode, us]

            engine.setPrimary(id: wetypePinyin.id)
            _ = engine.setLocked(true)

            // Initially only wetypePinyin is allowed
            assertEqual(engine.state.allowedIDs, [wetypePinyin.id], "Only wetypePinyin must be allowed")

            // When current is wetypePinyin, no action
            let actionSame = engine.handleSelectedSourceChanged(newSourceID: wetypePinyin.id, availableSources: sources)
            assertEqual(actionSame, .none, "Switch to same allowed source should be .none")

            // When switched to US, restore wetypePinyin
            let actionRestore = engine.handleSelectedSourceChanged(newSourceID: us.id, availableSources: sources)
            assertEqual(actionRestore, .selectSource(targetID: wetypePinyin.id), "Should restore wetypePinyin when US is selected")
        }

        // 4. 手动额外允许来源
        runTest("手动额外允许来源") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let british = makeSource(id: "com.apple.keylayout.British", name: "British", bundleID: "com.apple.keyboardlayout.all")
            let wetype = makeSource(id: "com.tencent.inputmethod.wetype.pinyin", name: "微信输入法", bundleID: "com.tencent.inputmethod.wetype")
            let us = makeSource(id: "com.apple.keylayout.US", name: "U.S.", bundleID: "com.apple.keyboardlayout.all")
            let sources = [british, wetype, us]

            engine.setPrimary(id: british.id)
            _ = engine.setLocked(true)

            // Manually allow wetype as an additional source
            engine.addAllowed(id: wetype.id)
            assertTrue(engine.state.allowedIDs.contains(wetype.id), "Allowed IDs should contain wetype")
            assertTrue(engine.state.allowedIDs.contains(british.id), "Allowed IDs should contain british")

            // Switch to wetype -> allowed, no-op, lastMemberID becomes wetype
            let actionWetype = engine.handleSelectedSourceChanged(newSourceID: wetype.id, availableSources: sources)
            assertEqual(actionWetype, .none, "Switching to manually allowed source should be .none")
            assertEqual(engine.state.lastMemberID, wetype.id, "lastMemberID should be updated to wetype")

            // Switch to disallowed US -> restores lastMemberID (wetype)
            let actionUS = engine.handleSelectedSourceChanged(newSourceID: us.id, availableSources: sources)
            assertEqual(actionUS, .selectSource(targetID: wetype.id), "Disallowed source should restore lastMemberID (wetype)")

            // Manually remove wetype
            engine.removeAllowed(id: wetype.id)
            assertFalse(engine.state.allowedIDs.contains(wetype.id), "wetype should no longer be in allowedIDs")
            assertEqual(engine.state.lastMemberID, british.id, "lastMemberID should revert to primary (british)")

            // Now switch to wetype is disallowed -> restores british
            let actionWetypeAfterRemove = engine.handleSelectedSourceChanged(newSourceID: wetype.id, availableSources: sources)
            assertEqual(actionWetypeAfterRemove, .selectSource(targetID: british.id), "Switch to removed source should restore primary (british)")
        }

        // 5. 目标禁用与启用变化后重试
        runTest("目标禁用与启用变化后重试") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let britishDisabled = makeSource(id: "com.apple.keylayout.British", name: "British", bundleID: "com.apple.keyboardlayout.all", enabled: false)
            let us = makeSource(id: "com.apple.keylayout.US", name: "U.S.", bundleID: "com.apple.keyboardlayout.all", enabled: true)

            engine.setPrimary(id: "com.apple.keylayout.British")
            _ = engine.setLocked(true)

            // Switched to US, but all allowed sources (British) are disabled
            let action = engine.handleSelectedSourceChanged(newSourceID: us.id, availableSources: [britishDisabled, us])
            assertEqual(action, .paused(reason: "所有已允许的输入法均不可用 (已暂停恢复)"), "Should pause when all allowed are disabled")
            assertTrue(engine.state.isPaused, "State isPaused should be true")
            assertNotNil(engine.state.pauseReason, "pauseReason should be set")

            // Subsequent switches are ignored while paused
            let actionIgnored = engine.handleSelectedSourceChanged(newSourceID: us.id, availableSources: [britishDisabled, us])
            assertEqual(actionIgnored, .none, "Switches while paused should produce .none")

            // Now British is enabled again, receiving kTISNotifyEnabledKeyboardInputSourcesChanged
            let britishEnabled = makeSource(id: "com.apple.keylayout.British", name: "British", bundleID: "com.apple.keyboardlayout.all", enabled: true)
            let retryAction = engine.handleEnabledSourcesChanged(availableSources: [britishEnabled, us], currentSelectedID: us.id)

            // Should unpause and restore British
            assertFalse(engine.state.isPaused, "Should resume from paused")
            assertNil(engine.state.pauseReason, "pauseReason should be cleared")
            assertEqual(retryAction, .selectSource(targetID: britishEnabled.id), "Should restore enabled British")
        }

        // 6. lastMember 失效回退 primary 再稳定排序
        runTest("lastMember 失效回退 primary 再稳定排序") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let primary = makeSource(id: "source.b.primary", name: "B Primary", bundleID: "bundle.b")
            let alt1 = makeSource(id: "source.a.alt1", name: "A Alt1", bundleID: "bundle.a")
            let alt2 = makeSource(id: "source.c.alt2", name: "C Alt2", bundleID: "bundle.c")
            let other = makeSource(id: "source.x.other", name: "X Other", bundleID: "bundle.x")

            engine.setPrimary(id: primary.id)
            engine.addAllowed(id: alt1.id)
            engine.addAllowed(id: alt2.id)
            _ = engine.setLocked(true)

            // Switch to alt1 -> becomes lastMemberID
            _ = engine.handleSelectedSourceChanged(newSourceID: alt1.id, availableSources: [primary, alt1, alt2, other])
            assertEqual(engine.state.lastMemberID, alt1.id)

            // Case A: alt1 becomes disabled. Primary is available.
            let alt1Disabled = makeSource(id: alt1.id, name: alt1.name, bundleID: alt1.bundleID, enabled: false)
            let actionFallbackPrimary = engine.handleSelectedSourceChanged(
                newSourceID: other.id,
                availableSources: [primary, alt1Disabled, alt2, other]
            )
            assertEqual(actionFallbackPrimary, .selectSource(targetID: primary.id), "Should fallback to primary when lastMember is disabled")

            // Case B: Both lastMember (alt1) AND primary are disabled!
            let primaryDisabled = makeSource(id: primary.id, name: primary.name, bundleID: primary.bundleID, enabled: false)
            let actionFallbackStableSort = engine.handleSelectedSourceChanged(
                newSourceID: other.id,
                availableSources: [primaryDisabled, alt1Disabled, alt2, other]
            )
            assertEqual(actionFallbackStableSort, .selectSource(targetID: alt2.id), "Should select only remaining allowed member")

            // Case C: When multiple remaining allowed sources are available and primary/lastMember are disabled, sort stably by name
            let alt3 = makeSource(id: "source.z.alt3", name: "A Alpha", bundleID: "bundle.z")
            engine.addAllowed(id: alt3.id)
            let actionStableSortByName = engine.handleSelectedSourceChanged(
                newSourceID: other.id,
                availableSources: [primaryDisabled, alt1Disabled, alt2, alt3, other]
            )
            // Between "A Alpha" (alt3) and "C Alt2" (alt2), "A Alpha" comes first
            assertEqual(actionStableSortByName, .selectSource(targetID: alt3.id), "Should sort remaining candidates stably by name")
        }

        // 7. 快速切换节流与连续失败熔断
        runTest("快速切换节流与连续失败熔断") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let primary = makeSource(id: "source.primary", name: "Primary", bundleID: "bundle.primary")
            let other = makeSource(id: "source.other", name: "Other", bundleID: "bundle.other")
            let sources = [primary, other]

            engine.setPrimary(id: primary.id)
            _ = engine.setLocked(true)

            let baseTime = Date()

            // 1 秒最多 3 次 select
            // Select 1
            let a1 = engine.handleSelectedSourceChanged(newSourceID: other.id, availableSources: sources, currentTime: baseTime)
            assertEqual(a1, .selectSource(targetID: primary.id))
            engine.recordSelectAttempt(currentTime: baseTime)
            engine.recordSelectResult(targetID: primary.id, success: true, currentTime: baseTime)

            // Select 2
            let a2 = engine.handleSelectedSourceChanged(newSourceID: other.id, availableSources: sources, currentTime: baseTime.addingTimeInterval(0.2))
            assertEqual(a2, .selectSource(targetID: primary.id))
            engine.recordSelectAttempt(currentTime: baseTime.addingTimeInterval(0.2))
            engine.recordSelectResult(targetID: primary.id, success: true, currentTime: baseTime.addingTimeInterval(0.2))

            // Select 3
            let a3 = engine.handleSelectedSourceChanged(newSourceID: other.id, availableSources: sources, currentTime: baseTime.addingTimeInterval(0.4))
            assertEqual(a3, .selectSource(targetID: primary.id))
            engine.recordSelectAttempt(currentTime: baseTime.addingTimeInterval(0.4))
            engine.recordSelectResult(targetID: primary.id, success: true, currentTime: baseTime.addingTimeInterval(0.4))

            // Select 4 within the same 1-second window -> throttled!
            let a4 = engine.handleSelectedSourceChanged(newSourceID: other.id, availableSources: sources, currentTime: baseTime.addingTimeInterval(0.6))
            assertEqual(a4, .paused(reason: "切换过于频繁，触发频率保护 (已暂停恢复)"))
            assertTrue(engine.state.isPaused)

            // Reset via re-lock
            _ = engine.setLocked(true)
            assertFalse(engine.state.isPaused)

            // Circuit breaker: 连续 3 次失败暂停
            let failureTime = baseTime.addingTimeInterval(5.0)
            engine.recordSelectResult(targetID: primary.id, success: false, currentTime: failureTime)
            assertEqual(engine.consecutiveFailures, 1)
            assertFalse(engine.state.isPaused)

            engine.recordSelectResult(targetID: primary.id, success: false, currentTime: failureTime)
            assertEqual(engine.consecutiveFailures, 2)
            assertFalse(engine.state.isPaused)

            engine.recordSelectResult(targetID: primary.id, success: false, currentTime: failureTime)
            assertEqual(engine.consecutiveFailures, 3)
            assertTrue(engine.state.isPaused)
            assertEqual(engine.state.pauseReason, "连续 3 次切换失败 (已暂停恢复)")

            // Re-locking resets consecutive failures
            _ = engine.setLocked(true)
            assertFalse(engine.state.isPaused)
            assertEqual(engine.consecutiveFailures, 0)
        }

        // 8. 连续切换 primary 移除旧 primary 并同步 lastMember (B1 修复验证)
        runTest("连续切换 primary 移除旧 primary 并同步 lastMember (B1 修复)") {
            let store = InMemoryLockStateStore()
            let engine = LockEngine(stateStore: store)

            let british = makeSource(id: "com.apple.keylayout.British", name: "British", bundleID: "com.apple.keyboardlayout.all")
            let wetype = makeSource(id: "com.tencent.inputmethod.wetype.pinyin", name: "微信输入法", bundleID: "com.tencent.inputmethod.wetype")
            let us = makeSource(id: "com.apple.keylayout.US", name: "U.S.", bundleID: "com.apple.keyboardlayout.all")
            let custom = makeSource(id: "com.custom.allowed", name: "Custom", bundleID: "com.custom")
            let sources = [british, wetype, us, custom]

            // Initial: set British as primary
            engine.setPrimary(id: british.id)
            _ = engine.setLocked(true)
            assertEqual(engine.state.primaryID, british.id)
            assertEqual(engine.state.allowedIDs, [british.id])
            assertEqual(engine.state.lastMemberID, british.id)

            // User manually adds extra allowed ID
            engine.addAllowed(id: custom.id)
            assertEqual(engine.state.allowedIDs, [british.id, custom.id])

            // First switch of primary: British -> WeType
            engine.setPrimary(id: wetype.id)
            // Old primary (British) MUST be removed from allowedIDs
            assertFalse(engine.state.allowedIDs.contains(british.id), "Old primary British must be removed from allowedIDs")
            assertTrue(engine.state.allowedIDs.contains(wetype.id), "New primary WeType must be in allowedIDs")
            assertTrue(engine.state.allowedIDs.contains(custom.id), "Manually added custom ID must be preserved")
            assertEqual(engine.state.allowedIDs, [wetype.id, custom.id])
            assertEqual(engine.state.lastMemberID, wetype.id, "lastMemberID should sync to new primary when it was old primary")

            // Switching to British must now be treated as DISALLOWED
            let actionBritish = engine.handleSelectedSourceChanged(newSourceID: british.id, availableSources: sources)
            assertEqual(actionBritish, .selectSource(targetID: wetype.id), "British should not be allowed after primary switched away")

            // Second consecutive switch of primary: WeType -> US
            engine.setPrimary(id: us.id)
            assertFalse(engine.state.allowedIDs.contains(wetype.id), "Previous primary WeType must be removed from allowedIDs")
            assertTrue(engine.state.allowedIDs.contains(us.id), "New primary US must be in allowedIDs")
            assertTrue(engine.state.allowedIDs.contains(custom.id), "Manually added custom ID must still be preserved")
            assertEqual(engine.state.allowedIDs, [us.id, custom.id])
            assertEqual(engine.state.lastMemberID, us.id, "lastMemberID should sync to new primary US")

            // Switching to WeType now must also be treated as DISALLOWED
            let actionWeType = engine.handleSelectedSourceChanged(newSourceID: wetype.id, availableSources: sources)
            assertEqual(actionWeType, .selectSource(targetID: us.id), "WeType should not be allowed after primary switched to US")

            // Switch to manually allowed custom: should be allowed (.none)
            let actionCustom = engine.handleSelectedSourceChanged(newSourceID: custom.id, availableSources: sources)
            assertEqual(actionCustom, .none)
            assertEqual(engine.state.lastMemberID, custom.id)

            // Third switch of primary while lastMember is custom:
            engine.setPrimary(id: british.id)
            assertFalse(engine.state.allowedIDs.contains(us.id))
            assertTrue(engine.state.allowedIDs.contains(british.id))
            assertEqual(engine.state.allowedIDs, [british.id, custom.id])
            // lastMember was custom, which is still in allowedIDs, so it should be preserved
            assertEqual(engine.state.lastMemberID, custom.id, "lastMember should be preserved when still in allowedIDs")
        }

        // 9. AppCoordinator 启动恢复与当前非允许源决策 (B2 修复验证)
        runTest("AppCoordinator 启动锁定状态恢复非允许当前源 (B2 修复)") {
            let british = makeSource(id: "com.apple.keylayout.British", name: "British", bundleID: "com.apple.keyboardlayout.all")
            let us = makeSource(id: "com.apple.keylayout.US", name: "U.S.", bundleID: "com.apple.keyboardlayout.all")
            let sources = [british, us]

            // Persisted state has isLocked = true, primary = British, allowed = [British]
            let initialState = LockState(
                primaryID: british.id,
                allowedIDs: [british.id],
                lastMemberID: british.id,
                isLocked: true
            )
            let store = InMemoryLockStateStore(initialState: initialState)
            let engine = LockEngine(stateStore: store)

            // Mock TIS: current source is US (disallowed!)
            let mockTIS = MockTISService(available: sources, current: us)
            let mockListener = MockNotificationListener()

            let coordinator = AppCoordinator(
                engine: engine,
                tisService: mockTIS,
                appNapManager: AppNapManager(),
                listener: mockListener
            )

            // Start coordinator: must detect locked + disallowed current, and immediately restore British!
            coordinator.start()

            assertEqual(mockTIS.selectedSourceID, british.id, "AppCoordinator.start() must restore to primary when locked and current is disallowed")
            assertTrue(mockListener.isListening, "Listener should start listening")
            coordinator.stop()
        }

        print("\n==================================================")
        print("Test Results: \(totalTests) test suites run, \(passedTests) assertions passed, \(failedTests) assertions failed.")
        if failedTests == 0 {
            print("🎉 All \(totalTests) test suites PASSED successfully!")
            print("==================================================")
            exit(0)
        } else {
            print("❌ Test failures detected!")
            print("==================================================")
            exit(1)
        }
    }
}

let runner = TestRunner()
runner.runAll()
