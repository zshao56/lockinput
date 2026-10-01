import Foundation
import AppKit
import InputSourceLockCore

@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    private let coordinator: AppCoordinator
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private lazy var allowedSourcesWindowController = AllowedSourcesWindowController(coordinator: coordinator)

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.menu = menu
        menu.delegate = self

        self.coordinator.onStateChanged = { [weak self] in
            self?.updateStatusItemUI()
        }

        updateStatusItemUI()
    }

    public func updateStatusItemUI() {
        let state = coordinator.engine.state
        let availableSources = coordinator.tisService.getKeyboardInputSources(includeAllInstalled: false)

        let primarySource = availableSources.first(where: { $0.id == state.primaryID })
        let primaryDisplayName = primarySource?.name ?? (state.primaryID ?? "未选择")

        if let button = statusItem.button {
            let badgeName: String
            let description: String
            if state.isPaused {
                badgeName = "exclamationmark.triangle.fill"
                description = "输入法锁定已暂停：\(state.pauseReason ?? "未知原因")"
            } else if state.isLocked {
                badgeName = "lock.fill"
                description = "已锁定输入法：\(primaryDisplayName)"
            } else {
                badgeName = "lock.open.fill"
                description = "输入法未锁定；主要输入法：\(primaryDisplayName)"
            }
            button.title = ""
            let letter = InputSourceMonogram.letter(name: primarySource?.name, id: state.primaryID)
            button.image = makeStatusImage(letter: letter, badgeName: badgeName)
            button.imagePosition = .imageOnly
            button.toolTip = description
        }
    }

    private func makeStatusImage(letter: String, badgeName: String) -> NSImage? {
        let badgeConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        guard let badge = NSImage(systemSymbolName: badgeName, accessibilityDescription: nil)?
                .withSymbolConfiguration(badgeConfig) else {
            return nil
        }

        let image = NSImage(size: NSSize(width: 28, height: 20), flipped: false) { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            let text = letter as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: max(0, (18 - textSize.width) / 2), y: (20 - textSize.height) / 2),
                withAttributes: attributes
            )
            badge.draw(in: NSRect(x: 17, y: 0, width: 11, height: 12))
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - NSMenuDelegate

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state = coordinator.engine.state
        let currentSource = coordinator.tisService.getCurrentKeyboardInputSource()
        let availableSources = coordinator.tisService.getKeyboardInputSources(includeAllInstalled: false)
        let selectableSources = availableSources.filter { $0.isSelectCapable }

        let primarySource = availableSources.first(where: { $0.id == state.primaryID })
        let primaryDisplayName = primarySource?.name ?? (state.primaryID ?? "未选择")

        // 1. Status Section
        let statusItem: NSMenuItem
        if state.isPaused {
            statusItem = NSMenuItem(title: "⚠️ 状态: 已暂停 - \(state.pauseReason ?? "未知原因")", action: nil, keyEquivalent: "")
        } else if state.isLocked {
            statusItem = NSMenuItem(title: "🟢 状态: 锁定中 (\(primaryDisplayName))", action: nil, keyEquivalent: "")
        } else {
            statusItem = NSMenuItem(title: "⚪️ 状态: 未锁定", action: nil, keyEquivalent: "")
        }
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let currentItem = NSMenuItem(
            title: "当前活跃: \(currentSource?.name ?? "未知") [\(currentSource?.id ?? "无")]",
            action: nil,
            keyEquivalent: ""
        )
        currentItem.isEnabled = false
        menu.addItem(currentItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Lock Toggle Item
        let lockToggleItem = NSMenuItem(
            title: state.isLocked ? "锁定已开启 (点击解锁)" : "锁定输入法 (点击锁定)",
            action: #selector(toggleLockClicked),
            keyEquivalent: "l"
        )
        lockToggleItem.target = self
        lockToggleItem.state = state.isLocked ? .on : .off
        menu.addItem(lockToggleItem)

        // 3. Primary Source Selection Submenu
        let primarySubmenu = NSMenu()
        let primaryMenuItem = NSMenuItem(title: "选择主要输入法 (Primary)", action: nil, keyEquivalent: "")
        primaryMenuItem.submenu = primarySubmenu

        for source in selectableSources {
            let item = NSMenuItem(
                title: "\(source.name) (\(source.id))",
                action: #selector(primarySourceSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = source.id
            if source.id == state.primaryID {
                item.state = .on
            }
            primarySubmenu.addItem(item)
        }
        menu.addItem(primaryMenuItem)

        // 4. Allowed Sources Window
        let allowedCount = state.allowedIDs.count
        let allowedItem = NSMenuItem(
            title: "管理额外允许的输入法... (已允许 \(allowedCount) 个)",
            action: #selector(openAllowedSourcesWindow),
            keyEquivalent: ""
        )
        allowedItem.target = self
        menu.addItem(allowedItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Refresh
        let refreshItem = NSMenuItem(
            title: "刷新输入法列表",
            action: #selector(refreshSourcesClicked),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Quit
        let quitItem = NSMenuItem(
            title: "退出 BoardLock",
            action: #selector(quitAppClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleLockClicked() {
        coordinator.toggleLock()
    }

    @objc private func primarySourceSelected(_ sender: NSMenuItem) {
        guard let sourceID = sender.representedObject as? String else { return }
        coordinator.setPrimary(id: sourceID)
    }

    @objc private func openAllowedSourcesWindow() {
        allowedSourcesWindowController.reloadSources()
        allowedSourcesWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshSourcesClicked() {
        coordinator.refreshSources()
    }

    @objc private func quitAppClicked() {
        NSApplication.shared.terminate(nil)
    }
}
