import Foundation
import AppKit
import InputSourceLockCore

@MainActor
public final class AllowedSourcesWindowController: NSWindowController {
    private let coordinator: AppCoordinator
    private var stackView: NSStackView!
    private var scrollView: NSScrollView!

    public init(coordinator: AppCoordinator) {
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "管理允许的输入法来源 (Allowed Sources)"
        window.center()
        super.init(window: window)

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = window else { return }

        let container = NSView(frame: window.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        window.contentView = container

        // Header / Description Label
        let headerLabel = NSTextField(labelWithString: "允许的输入法来源管理")
        headerLabel.font = NSFont.boldSystemFont(ofSize: 14)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerLabel)

        let descLabel = NSTextField(wrappingLabelWithString: "系统默认仅允许主要输入法（Primary），绝不按 Bundle ID 自动并组。\n若某些输入法的内部不同模式属于不同来源 ID，可在此手动勾选额外允许的来源。")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(descLabel)

        // Scroll view with stack view for items
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        container.addSubview(scrollView)

        let clipView = NSClipView()
        scrollView.contentView = clipView

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = stackView

        // Close button
        let closeButton = NSButton(title: "完成", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(closeButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            descLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -12),

            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),

            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        reloadSources()
    }

    public func reloadSources() {
        stackView.subviews.forEach { $0.removeFromSuperview() }

        let allSources = coordinator.tisService.getKeyboardInputSources(includeAllInstalled: false)
        let selectable = allSources.filter { $0.isSelectCapable }
        let currentPrimary = coordinator.engine.state.primaryID
        let allowed = coordinator.engine.state.allowedIDs

        for source in selectable {
            let row = makeSourceRow(source: source, isPrimary: source.id == currentPrimary, isAllowed: allowed.contains(source.id))
            stackView.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 10).isActive = true
            row.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -10).isActive = true
        }
    }

    private func makeSourceRow(source: InputSourceInfo, isPrimary: Bool, isAllowed: Bool) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleSourceAllowed(_:)))
        checkbox.state = (isPrimary || isAllowed) ? .on : .off
        checkbox.isEnabled = !isPrimary // Primary is always allowed, cannot be unchecked
        checkbox.identifier = NSUserInterfaceItemIdentifier(source.id)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(checkbox)

        let titleText = isPrimary ? "\(source.name)  [主要输入法 (Primary)]" : source.name
        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = isPrimary ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(titleLabel)

        let detailText = "ID: \(source.id)  |  Bundle: \(source.bundleID)"
        let detailLabel = NSTextField(labelWithString: detailText)
        detailLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: rowView.leadingAnchor),
            checkbox.topAnchor.constraint(equalTo: rowView.topAnchor, constant: 2),

            titleLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: rowView.topAnchor),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -4)
        ])

        return rowView
    }

    @objc private func toggleSourceAllowed(_ sender: NSButton) {
        guard let sourceID = sender.identifier?.rawValue else { return }
        if sender.state == .on {
            coordinator.addAllowed(id: sourceID)
        } else {
            coordinator.removeAllowed(id: sourceID)
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
