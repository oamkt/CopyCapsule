import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Manages the menu bar icon and window panel lifecycle.
/// Uses NSWindow (not NSPopover) to support user resizing.
/// Bridges AppKit (NSStatusItem, NSWindow) with SwiftUI views.
/// The window is pinned below the status item and tracks its position.
@MainActor
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private let viewModel: ClipHistoryViewModel
    private var localKeyMonitor: Any?
    private var screenParamsObserver: NSObjectProtocol?

    init(viewModel: ClipHistoryViewModel) {
        self.viewModel = viewModel
        super.init()
        setupStatusItem()
        setupWindow()
        setupScreenObserver()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }

        // Use SF Symbol clipboard icon, template mode adapts to light/dark menu bar
        if let image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "CopyCapsule"
        ) {
            image.isTemplate = true
            button.image = image
        }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.toolTip = "CopyCapsule — Clipboard History"
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseDown {
            let menu = NSMenu()
            let quitItem = NSMenuItem(
                title: "退出 CopyCapsule",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
            quitItem.keyEquivalentModifierMask = [.command]
            menu.addItem(quitItem)
            NSMenu.popUpContextMenu(menu, with: event, for: statusItem.button!)
        } else {
            toggleWindow()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Screen Observer

    /// Observe screen parameter changes (displays connect/disconnect, resolution change)
    /// so the window stays pinned to the status item.
    private func setupScreenObserver() {
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let window = self.window, window.isVisible else { return }
                self.repositionWindow()
            }
        }
    }

    // MARK: - Window

    private func setupWindow() {
        let rootView = HistoryPanelView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = ""
        window.setContentSize(NSSize(width: 380, height: 560))
        window.minSize = NSSize(width: 300, height: 400)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor.windowBackgroundColor
        // Prevent user dragging the window away from the menu bar
        window.isMovable = false

        self.window = window

        // Monitor Escape + shortcut keys
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let settings = AppSettings.shared
            if event.keyCode == 53 { // Escape
                self?.viewModel.clearSelection()
                self?.closeWindow()
                return nil
            }
            if settings.tagShortcut.matches(event: event) {
                Task { @MainActor in
                    guard let vm = self?.viewModel, !vm.selectedItemIDs.isEmpty else { return }
                    vm.taggingItemIDs = vm.selectedItemIDs
                    vm.tagInputText = ""
                    vm.showTagInput = true
                }
                return nil
            }
            if settings.exportShortcut.matches(event: event) {
                Task { @MainActor in self?.handleExport() }
                return nil
            }
            if settings.windowShortcut.matches(event: event) {
                self?.toggleWindow()
                return nil
            }
            return event
        }
    }

    // MARK: - Positioning

    /// Reposition the window so it's always centered below the status item.
    private func repositionWindow() {
        guard let window else { return }

        // Determine screen: prefer the screen containing the status item,
        // fall back to the main screen so the window never gets stranded.
        let screen: NSScreen? = statusItem.button?.window?.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowRect = window.frame

        // Horizontal: center under the status item, or center on screen as fallback
        // Vertical: below the menu bar status item, or top of visible frame as fallback
        let newOrigin: NSPoint
        if let button = statusItem.button {
            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            if let buttonWindow = button.window {
                let buttonRect = buttonWindow.convertToScreen(buttonRectInWindow)
                newOrigin = NSPoint(
                    x: buttonRect.midX - windowRect.width / 2,
                    y: buttonRect.minY - windowRect.height - 4
                )
            } else {
                newOrigin = NSPoint(
                    x: screenFrame.midX - windowRect.width / 2,
                    y: screenFrame.maxY - windowRect.height
                )
            }
        } else {
            newOrigin = NSPoint(
                x: screenFrame.midX - windowRect.width / 2,
                y: screenFrame.maxY - windowRect.height
            )
        }

        var origin = newOrigin

        // Keep window on screen horizontally
        if origin.x + windowRect.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - windowRect.width - 8
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + 8
        }

        // Keep window vertically within visible frame
        if origin.y + windowRect.height > screenFrame.maxY {
            origin.y = screenFrame.maxY - windowRect.height - 8
        }
        if origin.y < screenFrame.minY {
            origin.y = screenFrame.minY + 8
        }

        window.setFrameOrigin(origin)
    }

    // MARK: - Actions

    @objc func toggleWindow() {
        guard let window else { return }

        if window.isVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }

    func showWindow() {
        guard let window, statusItem.button != nil else { return }

        // Refresh data each time the window opens
        viewModel.refresh()

        // Pin window below the menu bar icon
        repositionWindow()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    // MARK: - Export

    private func handleExport() {
        let tags = viewModel.selectedTags
        guard !tags.isEmpty else {
            viewModel.errorMessage = "请先选择标签后再导出"
            return
        }

        let savePanel = NSSavePanel()
        let tagLabel = tags.sorted().joined(separator: "+")
        savePanel.title = "导出 \(tags.count) 个标签组"
        savePanel.nameFieldStringValue = "\(tagLabel).md"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true

        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            let vm = self?.viewModel
            Task { @MainActor in
                vm?.exportSelectedTags(format: .markdown, to: url)
            }
        }
    }

    // MARK: - Cleanup

    func remove() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let observer = screenParamsObserver {
            NotificationCenter.default.removeObserver(observer)
            screenParamsObserver = nil
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

// MARK: - NSWindowDelegate

extension MenuBarManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Called when user clicks the red close button.
        // We just hide the window rather than destroying it.
    }

    func windowDidResignKey(_ notification: Notification) {
        // Window stays visible when losing focus (unlike popover).
        // User must click the menu bar icon or press Esc to close.
    }

    func windowDidResize(_ notification: Notification) {
        // Recenter horizontally when user resizes the window
        repositionWindow()
    }
}
