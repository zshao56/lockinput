import Foundation
import AppKit
import Carbon

@MainActor
public protocol NotificationListenerDelegate: AnyObject {
    func didChangeSelectedKeyboardInputSource()
    func didChangeEnabledKeyboardInputSources()
}

@MainActor
public protocol NotificationListenerProtocol: AnyObject {
    var delegate: NotificationListenerDelegate? { get set }
    func startListening()
    func stopListening()
}

public final class NotificationListener: NSObject, NotificationListenerProtocol, @unchecked Sendable {
    public weak var delegate: NotificationListenerDelegate?
    private let center = DistributedNotificationCenter.default()

    private let selectedSourceChangedName = NSNotification.Name((kTISNotifySelectedKeyboardInputSourceChanged as CFString) as String)
    private let enabledSourcesChangedName = NSNotification.Name((kTISNotifyEnabledKeyboardInputSourcesChanged as CFString) as String)

    public override init() {
        super.init()
    }

    public func startListening() {
        center.addObserver(
            self,
            selector: #selector(handleSelectedSourceChanged),
            name: selectedSourceChangedName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        center.addObserver(
            self,
            selector: #selector(handleEnabledSourcesChanged),
            name: enabledSourcesChangedName,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    public func stopListening() {
        center.removeObserver(self, name: selectedSourceChangedName, object: nil)
        center.removeObserver(self, name: enabledSourcesChangedName, object: nil)
    }

    @objc private func handleSelectedSourceChanged(_ notification: Notification) {
        Task { @MainActor in
            self.delegate?.didChangeSelectedKeyboardInputSource()
        }
    }

    @objc private func handleEnabledSourcesChanged(_ notification: Notification) {
        Task { @MainActor in
            self.delegate?.didChangeEnabledKeyboardInputSources()
        }
    }

    deinit {
        center.removeObserver(self)
    }
}
