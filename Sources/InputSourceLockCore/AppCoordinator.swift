import Foundation
import AppKit

@MainActor
public final class AppCoordinator: NotificationListenerDelegate {
    public let engine: LockEngine
    public let tisService: TISServiceProtocol
    public let appNapManager: AppNapManager
    public let listener: NotificationListenerProtocol

    public var onStateChanged: (() -> Void)?

    private var debounceWorkItem: DispatchWorkItem?
    private var enabledDebounceWorkItem: DispatchWorkItem?
    private var isRestoringFlight: Bool = false
    private(set) public var expectedSelfSelectedID: String?

    public init(
        engine: LockEngine,
        tisService: TISServiceProtocol = TISService(),
        appNapManager: AppNapManager = AppNapManager(),
        listener: NotificationListenerProtocol = NotificationListener()
    ) {
        self.engine = engine
        self.tisService = tisService
        self.appNapManager = appNapManager
        self.listener = listener

        self.listener.delegate = self
    }

    public func start() {
        appNapManager.beginActivity()
        listener.startListening()

        // Initialize primaryID if not set
        let currentSources = tisService.getKeyboardInputSources(includeAllInstalled: false)
        let selectableEnabled = currentSources.filter { $0.isEnabled && $0.isSelectCapable }

        if engine.state.primaryID == nil {
            if let active = tisService.getCurrentKeyboardInputSource(), active.isSelectCapable {
                engine.setPrimary(id: active.id)
            } else if let first = selectableEnabled.first {
                engine.setPrimary(id: first.id)
            }
        }

        // B2 Fix: If locked upon launch and current source is disallowed, restore immediately
        if engine.state.isLocked, let current = tisService.getCurrentKeyboardInputSource() {
            if !engine.state.allowedIDs.contains(current.id) {
                let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
                let action = engine.handleSelectedSourceChanged(newSourceID: current.id, availableSources: available)
                executeEngineAction(action)
            }
        }

        onStateChanged?()
    }

    public func stop() {
        debounceWorkItem?.cancel()
        enabledDebounceWorkItem?.cancel()
        listener.stopListening()
        appNapManager.endActivity()
    }

    // MARK: - User Intent Actions

    public func toggleLock() {
        let current = tisService.getCurrentKeyboardInputSource()
        let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
        let newLocked = !engine.state.isLocked

        let action = engine.setLocked(
            newLocked,
            currentSelectedID: current?.id,
            availableSources: available
        )

        executeEngineAction(action)
        onStateChanged?()
    }

    public func setPrimary(id: String) {
        engine.setPrimary(id: id)
        if engine.state.isLocked {
            let current = tisService.getCurrentKeyboardInputSource()
            let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
            if let currentID = current?.id, !engine.state.allowedIDs.contains(currentID) {
                let action = engine.handleSelectedSourceChanged(newSourceID: currentID, availableSources: available)
                executeEngineAction(action)
            }
        }
        onStateChanged?()
    }

    public func addAllowed(id: String) {
        engine.addAllowed(id: id)
        onStateChanged?()
    }

    public func removeAllowed(id: String) {
        engine.removeAllowed(id: id)
        if engine.state.isLocked {
            let current = tisService.getCurrentKeyboardInputSource()
            let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
            if let currentID = current?.id, !engine.state.allowedIDs.contains(currentID) {
                let action = engine.handleSelectedSourceChanged(newSourceID: currentID, availableSources: available)
                executeEngineAction(action)
            }
        }
        onStateChanged?()
    }

    public func refreshSources() {
        enabledDebounceWorkItem?.cancel()
        performEnabledSourcesChanged()
    }

    // MARK: - NotificationListenerDelegate

    public func didChangeSelectedKeyboardInputSource() {
        // ~150ms Debounce
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSelectedSourceChanged()
        }
        self.debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    public func didChangeEnabledKeyboardInputSources() {
        // ~150ms Debounce
        enabledDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performEnabledSourcesChanged()
        }
        self.enabledDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    // MARK: - Internal Handling

    private func performEnabledSourcesChanged() {
        let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
        let current = tisService.getCurrentKeyboardInputSource()
        let action = engine.handleEnabledSourcesChanged(
            availableSources: available,
            currentSelectedID: current?.id
        )
        executeEngineAction(action)
        onStateChanged?()
    }

    private func performSelectedSourceChanged() {
        guard let current = tisService.getCurrentKeyboardInputSource() else {
            onStateChanged?()
            return
        }

        // Self-triggered check: if expectedSelfSelectedID exists, check against current.id
        if let expected = expectedSelfSelectedID {
            if expected == current.id {
                expectedSelfSelectedID = nil
                engine.recordSelectResult(targetID: current.id, success: true)
                onStateChanged?()
                return
            } else {
                // Actual current != expected: clear expected ID and record failure to prevent residue
                expectedSelfSelectedID = nil
                engine.recordSelectResult(targetID: expected, success: false)
            }
        }

        // Action before pre-check: if newly selected is in allowedIDs, it's allowed
        if engine.state.allowedIDs.contains(current.id) {
            let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
            _ = engine.handleSelectedSourceChanged(newSourceID: current.id, availableSources: available)
            onStateChanged?()
            return
        }

        guard engine.state.isLocked else {
            onStateChanged?()
            return
        }

        guard !isRestoringFlight else {
            return
        }

        let available = tisService.getKeyboardInputSources(includeAllInstalled: false)
        let action = engine.handleSelectedSourceChanged(newSourceID: current.id, availableSources: available)
        executeEngineAction(action)
        onStateChanged?()
    }

    private func executeEngineAction(_ action: EngineAction) {
        switch action {
        case .none:
            break

        case .paused(let reason):
            print("[InputSourceLock] Paused restoration: \(reason)")

        case .selectSource(let targetID):
            guard !isRestoringFlight else { return }
            isRestoringFlight = true
            defer { isRestoringFlight = false }

            // Pre-action re-check: verify current active source right before select
            if let latest = tisService.getCurrentKeyboardInputSource() {
                if engine.state.allowedIDs.contains(latest.id) {
                    return
                }
            }

            engine.recordSelectAttempt()
            expectedSelfSelectedID = targetID
            let success = tisService.selectInputSource(id: targetID)
            if !success {
                expectedSelfSelectedID = nil
                engine.recordSelectResult(targetID: targetID, success: false)
                print("[InputSourceLock] Failed to select input source: \(targetID)")
            }
        }
    }
}
