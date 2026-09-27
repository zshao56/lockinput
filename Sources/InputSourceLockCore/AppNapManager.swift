import Foundation

public final class AppNapManager: @unchecked Sendable {
    private var activityToken: NSObjectProtocol?
    private let lock = NSLock()

    public init() {}

    public func beginActivity(reason: String = "Keep InputSourceLock active for TIS notifications and fast debounce") {
        lock.lock()
        defer { lock.unlock() }

        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: reason
        )
    }

    public func endActivity() {
        lock.lock()
        defer { lock.unlock() }

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }

    deinit {
        endActivity()
    }
}
