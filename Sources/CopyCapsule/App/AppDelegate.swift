import AppKit
import SwiftUI
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var clipboardMonitor: ClipboardMonitor?
    private var hotKeyManager: HotKeyManager?
    private var retentionService: RetentionService?
    private var repository: ClipRepository?
    private var viewModel: ClipHistoryViewModel?
    private var updaterController: SPUStandardUpdaterController?
    private var globalQuitMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Global ⌘Q — quit from anywhere without needing the window open
        globalQuitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.keyCode == 12 { // keyCode 12 = Q
                NSApp.terminate(nil)
            }
            return event
        }

        let dbURL = databaseURL()
        let repository: ClipRepository
        do { repository = try ClipRepository(dbPath: dbURL.path); self.repository = repository }
        catch { NSApp.terminate(nil); return }

        // Seed built-in guide on first launch
        try? GuideSeeder.seedIfNeeded(into: repository)

        let viewModel = ClipHistoryViewModel(repository: repository)
        self.viewModel = viewModel

        let dedupService = DedupService()
        clipboardMonitor = ClipboardMonitor(dedupService: dedupService, repository: repository)
        clipboardMonitor?.onNewItem = { [weak viewModel] item in
            Task { @MainActor in viewModel?.prependItem(item) }
        }
        viewModel.onReCopy = { [weak clipboardMonitor] in clipboardMonitor?.syncChangeCount() }
        clipboardMonitor?.startPolling()

        menuBarManager = MenuBarManager(viewModel: viewModel)
        registerCarbonHotkey()

        AppSettings.shared.onWindowShortcutChange = { [weak self] in
            Task { @MainActor in self?.registerCarbonHotkey() }
        }

        let settings = AppSettings.shared
        settings.applyAppearance()
        retentionService = RetentionService(repository: repository, settings: settings)
        retentionService?.start()
        LoginItemManager.syncWithSetting(settings.autoStartEnabled)

        // Sparkle auto-updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private func registerCarbonHotkey() {
        // Always unregister first to ensure clean state
        if let hk = hotKeyManager {
            hk.unregister()
        }
        hotKeyManager = HotKeyManager()

        let sc = AppSettings.shared.windowShortcut
        let ns = NSEvent.ModifierFlags(rawValue: sc.modifiers).intersection(.deviceIndependentFlagsMask)

        var mods = HotKeyManager.Modifier()
        if ns.contains(.command) { mods.insert(.command) }
        if ns.contains(.shift)   { mods.insert(.shift) }
        if ns.contains(.option)  { mods.insert(.option) }
        if ns.contains(.control) { mods.insert(.control) }
        // Carbon requires at least one meta modifier
        if !ns.contains(.command) && !ns.contains(.option) && !ns.contains(.control) {
            mods.insert(.command)
        }

        hotKeyManager?.register(key: .raw(UInt32(sc.keyCode)), modifiers: mods) { [weak self] in
            self?.menuBarManager?.toggleWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalQuitMonitor {
            NSEvent.removeMonitor(monitor)
        }
        clipboardMonitor?.stopPolling()
        retentionService?.stop()
        hotKeyManager?.unregister()
        menuBarManager?.remove()
    }

    private func databaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("CopyCapsule")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("copycapsule.sqlite")
    }
}
