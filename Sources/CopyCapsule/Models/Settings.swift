import Foundation
import AppKit

/// Application-wide settings backed by UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum HotKeyMode: Int {
        case shiftOnly = 0
        case shiftCommand = 1
    }

    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: keyRetentionDays) }
    }

    var autoStartEnabled: Bool {
        didSet { UserDefaults.standard.set(autoStartEnabled, forKey: keyAutoStart) }
    }

    var hotKeyMode: HotKeyMode {
        didSet { UserDefaults.standard.set(hotKeyMode.rawValue, forKey: keyHotKeyMode) }
    }

    var tagShortcut: Shortcut {
        didSet { saveShortcut(tagShortcut, forKey: keyTagShortcut) }
    }
    var windowShortcut: Shortcut {
        didSet {
            saveShortcut(windowShortcut, forKey: keyWindowShortcut)
            onWindowShortcutChange?()
        }
    }
    var exportShortcut: Shortcut {
        didSet { saveShortcut(exportShortcut, forKey: keyExportShortcut) }
    }
    var useDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(useDarkMode, forKey: keyDarkMode)
            applyAppearance()
        }
    }

    /// Whether the user has explicitly chosen an appearance mode.
    /// New installs return false → the app follows the system appearance.
    var hasSetAppearance: Bool {
        UserDefaults.standard.object(forKey: keyDarkMode) != nil
    }
    var onWindowShortcutChange: (() -> Void)?

    private init() {
        let ud = UserDefaults.standard
        let storedDays = ud.integer(forKey: keyRetentionDays)
        self.retentionDays = (storedDays > 0) ? storedDays : 3
        self.autoStartEnabled = ud.bool(forKey: keyAutoStart)
        let mode = ud.integer(forKey: keyHotKeyMode)
        self.hotKeyMode = HotKeyMode(rawValue: mode) ?? .shiftCommand
        self.tagShortcut = Self.loadShortcut(default: .defaultTagInput, forKey: keyTagShortcut)
        self.windowShortcut = Self.loadShortcut(default: .defaultToggleWindow, forKey: keyWindowShortcut)
        self.exportShortcut = Self.loadShortcut(default: .defaultExport, forKey: keyExportShortcut)
        self.useDarkMode = ud.object(forKey: keyDarkMode) as? Bool ?? false
    }

    func applyAppearance() {
        guard hasSetAppearance else {
            NSApp.appearance = nil // follow system
            return
        }
        NSApp.appearance = NSAppearance(named: useDarkMode ? .darkAqua : .aqua)
    }

    /// Shift-click the theme button to reset back to "follow system".
    func resetAppearance() {
        UserDefaults.standard.removeObject(forKey: keyDarkMode)
        NSApp.appearance = nil
    }

    private func saveShortcut(_ s: Shortcut, forKey key: String) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadShortcut(default def: Shortcut, forKey key: String) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return def }
        return s
    }
}

private let keyRetentionDays = "retentionDays"
private let keyAutoStart = "autoStartEnabled"
private let keyHotKeyMode = "hotKeyMode"
private let keyTagShortcut = "tagShortcut"
private let keyWindowShortcut = "windowShortcut"
private let keyExportShortcut = "exportShortcut"
private let keyDarkMode = "useDarkMode"
