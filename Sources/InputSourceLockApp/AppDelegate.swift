import Foundation
import AppKit
import InputSourceLockCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator!
    private var menuController: StatusMenuController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let store = UserDefaultsLockStateStore()
        let engine = LockEngine(stateStore: store)
        let tisService = TISService()
        let appNapManager = AppNapManager()
        let listener = NotificationListener()

        coordinator = AppCoordinator(
            engine: engine,
            tisService: tisService,
            appNapManager: appNapManager,
            listener: listener
        )

        menuController = StatusMenuController(coordinator: coordinator)
        coordinator.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
