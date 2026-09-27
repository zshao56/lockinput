import Foundation

public enum EngineAction: Equatable, Sendable {
    case none
    case selectSource(targetID: String)
    case paused(reason: String)
}

public final class LockEngine: @unchecked Sendable {
    private let stateStore: LockStateStoreProtocol
    private let lock = NSLock()

    private(set) public var state: LockState
    private(set) public var consecutiveFailures: Int = 0
    private var recentSelectTimestamps: [Date] = []

    public init(stateStore: LockStateStoreProtocol = InMemoryLockStateStore()) {
        self.stateStore = stateStore
        self.state = stateStore.load()
    }

    // MARK: - State Accessors & Mutators

    public func setLocked(
        _ locked: Bool,
        currentSelectedID: String? = nil,
        availableSources: [InputSourceInfo] = [],
        currentTime: Date = Date()
    ) -> EngineAction {
        lock.lock()
        defer { lock.unlock() }

        state.isLocked = locked
        state.isPaused = false
        state.pauseReason = nil
        consecutiveFailures = 0

        stateStore.save(state)

        if locked, let currentID = currentSelectedID {
            return decideRestorationActionLocked(
                currentSelectedID: currentID,
                availableSources: availableSources,
                currentTime: currentTime
            )
        }
        return .none
    }

    public func setPrimary(id: String) {
        lock.lock()
        defer { lock.unlock() }

        let oldPrimary = state.primaryID
        if let oldPrimary = oldPrimary, oldPrimary != id {
            state.allowedIDs.remove(oldPrimary)
            if state.lastMemberID == oldPrimary {
                state.lastMemberID = id
            }
        }
        state.primaryID = id
        state.allowedIDs.insert(id)
        if state.lastMemberID == nil || !state.allowedIDs.contains(state.lastMemberID!) {
            state.lastMemberID = id
        }
        stateStore.save(state)
    }

    public func addAllowed(id: String) {
        lock.lock()
        defer { lock.unlock() }

        state.allowedIDs.insert(id)
        stateStore.save(state)
    }

    public func removeAllowed(id: String) {
        lock.lock()
        defer { lock.unlock() }

        // Primary cannot be removed from allowedIDs
        if id != state.primaryID {
            state.allowedIDs.remove(id)
            if state.lastMemberID == id {
                state.lastMemberID = state.primaryID
            }
            stateStore.save(state)
        }
    }

    public func setAllowed(ids: Set<String>) {
        lock.lock()
        defer { lock.unlock() }

        var newSet = ids
        if let primary = state.primaryID {
            newSet.insert(primary)
        }
        state.allowedIDs = newSet
        if let last = state.lastMemberID, !state.allowedIDs.contains(last) {
            state.lastMemberID = state.primaryID
        }
        stateStore.save(state)
    }

    // MARK: - TIS Notification Handlers

    public func handleSelectedSourceChanged(
        newSourceID: String,
        availableSources: [InputSourceInfo],
        currentTime: Date = Date()
    ) -> EngineAction {
        lock.lock()
        defer { lock.unlock() }

        guard state.isLocked else { return .none }
        guard !state.isPaused else { return .none }

        // If newly selected source is already in allowedIDs, record it as lastMemberID and do nothing
        if state.allowedIDs.contains(newSourceID) {
            state.lastMemberID = newSourceID
            stateStore.save(state)
            return .none
        }

        // Switched to disallowed source -> restore
        return decideRestorationActionLocked(
            currentSelectedID: newSourceID,
            availableSources: availableSources,
            currentTime: currentTime
        )
    }

    public func handleEnabledSourcesChanged(
        availableSources: [InputSourceInfo],
        currentSelectedID: String?,
        currentTime: Date = Date()
    ) -> EngineAction {
        lock.lock()
        defer { lock.unlock() }

        guard state.isLocked else { return .none }

        // Check if any allowed source is enabled and selectable
        let validCandidates = getValidCandidatesLocked(availableSources: availableSources)

        // If we were paused and now have valid candidates, resume
        if state.isPaused && !validCandidates.isEmpty {
            state.isPaused = false
            state.pauseReason = nil
            consecutiveFailures = 0
            stateStore.save(state)
        }

        guard !state.isPaused else { return .none }

        if let currentID = currentSelectedID, !state.allowedIDs.contains(currentID) {
            return decideRestorationActionLocked(
                currentSelectedID: currentID,
                availableSources: availableSources,
                currentTime: currentTime
            )
        }

        return .none
    }

    // MARK: - Execution & Circuit Breaker Tracking

    public func recordSelectAttempt(currentTime: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        recentSelectTimestamps.append(currentTime)
        pruneOldTimestamps(currentTime: currentTime)
    }

    public func recordSelectResult(targetID: String, success: Bool, currentTime: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        if success {
            consecutiveFailures = 0
            state.lastMemberID = targetID
            stateStore.save(state)
        } else {
            consecutiveFailures += 1
            if consecutiveFailures >= 3 {
                state.isPaused = true
                state.pauseReason = "连续 3 次切换失败 (已暂停恢复)"
                stateStore.save(state)
            }
        }
    }

    // MARK: - Internal Decision Logic

    private func decideRestorationActionLocked(
        currentSelectedID: String,
        availableSources: [InputSourceInfo],
        currentTime: Date
    ) -> EngineAction {
        let validCandidates = getValidCandidatesLocked(availableSources: availableSources)

        if validCandidates.isEmpty {
            let reason = "所有已允许的输入法均不可用 (已暂停恢复)"
            state.isPaused = true
            state.pauseReason = reason
            stateStore.save(state)
            return .paused(reason: reason)
        }

        // Target candidate selection:
        // 1. If lastMemberID is valid & enabled, choose it
        // 2. Else if primaryID is valid & enabled, choose it
        // 3. Else fallback to stable sort of valid candidates
        let targetID: String
        let validCandidateIDs = Set(validCandidates.map(\.id))

        if let lastMember = state.lastMemberID,
           state.allowedIDs.contains(lastMember),
           validCandidateIDs.contains(lastMember) {
            targetID = lastMember
        } else if let primary = state.primaryID,
                  validCandidateIDs.contains(primary) {
            targetID = primary
        } else {
            let sorted = validCandidates.sorted {
                let nameCompare = $0.name.localizedStandardCompare($1.name)
                if nameCompare == .orderedSame {
                    return $0.id < $1.id
                }
                return nameCompare == .orderedAscending
            }
            targetID = sorted.first!.id
        }

        // Rate limit check: at most 3 selects within 1.0 second
        pruneOldTimestamps(currentTime: currentTime)
        if recentSelectTimestamps.count >= 3 {
            let reason = "切换过于频繁，触发频率保护 (已暂停恢复)"
            state.isPaused = true
            state.pauseReason = reason
            stateStore.save(state)
            return .paused(reason: reason)
        }

        // Consecutive failure check
        if consecutiveFailures >= 3 {
            let reason = "连续 3 次切换失败 (已暂停恢复)"
            state.isPaused = true
            state.pauseReason = reason
            stateStore.save(state)
            return .paused(reason: reason)
        }

        return .selectSource(targetID: targetID)
    }

    private func getValidCandidatesLocked(availableSources: [InputSourceInfo]) -> [InputSourceInfo] {
        return availableSources.filter { source in
            state.allowedIDs.contains(source.id) && source.isEnabled && source.isSelectCapable
        }
    }

    private func pruneOldTimestamps(currentTime: Date) {
        recentSelectTimestamps = recentSelectTimestamps.filter { timestamp in
            currentTime.timeIntervalSince(timestamp) < 1.0
        }
    }
}
