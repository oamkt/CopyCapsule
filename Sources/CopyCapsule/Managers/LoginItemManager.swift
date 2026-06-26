import ServiceManagement

/// Manages the "Launch at Login" setting via SMAppService (macOS 13+).
///
/// Requirements:
/// - App must be inside a .app bundle
/// - App must be code-signed (ad-hoc signing via `codesign --sign -` is sufficient)
///
/// These are both handled by `Scripts/build.sh`.
enum LoginItemManager {
    /// Register the app as a login item. Fails gracefully with a printed error.
    static func enable() {
        do {
            try SMAppService.mainApp.register()
            print("[CopyCapsule] Login item enabled")
        } catch {
            print("[CopyCapsule] Failed to register login item: \(error.localizedDescription)")
            // Common cause: app not in .app bundle or not signed.
            // The app continues to function without this feature.
        }
    }

    /// Unregister the app as a login item.
    static func disable() {
        do {
            try SMAppService.mainApp.unregister()
            print("[CopyCapsule] Login item disabled")
        } catch {
            print("[CopyCapsule] Failed to unregister login item: \(error.localizedDescription)")
        }
    }

    /// Whether the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Synchronize the login item state with the current setting.
    /// Always re-registers when enabled to ensure the login item points to the current bundle
    /// (important after rebuilds that delete and recreate the .app bundle).
    static func syncWithSetting(_ autoStartEnabled: Bool) {
        if autoStartEnabled {
            // Disable first to clear any stale registration, then re-enable.
            try? SMAppService.mainApp.unregister()
            enable()
        } else {
            guard isEnabled else { return }
            disable()
        }
    }
}
