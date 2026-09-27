import Foundation

public protocol LockStateStoreProtocol: AnyObject, Sendable {
    func load() -> LockState
    func save(_ state: LockState)
}

public final class InMemoryLockStateStore: LockStateStoreProtocol, @unchecked Sendable {
    private var state: LockState
    private let lock = NSLock()

    public init(initialState: LockState = LockState()) {
        self.state = initialState
    }

    public func load() -> LockState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func save(_ state: LockState) {
        lock.lock()
        defer { lock.unlock() }
        self.state = state
    }
}

public final class UserDefaultsLockStateStore: LockStateStoreProtocol, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.inputsourcelock.state"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LockState {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: key) else {
            return LockState(isLocked: false)
        }
        do {
            var decoded = try JSONDecoder().decode(LockState.self, from: data)
            // Runtime pause status is reset upon fresh app launch
            decoded.isPaused = false
            decoded.pauseReason = nil
            return decoded
        } catch {
            return LockState(isLocked: false)
        }
    }

    public func save(_ state: LockState) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: key)
        } catch {
            // Log or ignore
        }
    }
}
