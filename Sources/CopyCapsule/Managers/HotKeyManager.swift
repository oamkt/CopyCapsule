import Carbon
import AppKit

/// Registers a global hotkey (⇧⌘V) via Carbon Event Manager.
/// Works without accessibility permissions — the only reliable zero-permission approach.
///
/// Marked `@unchecked Sendable` because Carbon callbacks arrive on arbitrary threads,
/// but we always dispatch to main before accessing stored state.
final class HotKeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// The action to perform when the hotkey is pressed.
    fileprivate var actionHandler: (() -> Void)?

    // Signature for our hotkey — "Clik" as a FourCharCode
    private static let signature: FourCharCode = 0x436C696B

    deinit {
        unregister()
    }

    // MARK: - Register

    func register(key: Key, modifiers: Modifier, action: @escaping () -> Void) {
        self.actionHandler = action

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: 1
        )

        let status = RegisterEventHotKey(
            key.carbonKeyCode,
            modifiers.carbonFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            print("[CopyCapsule] HotKey registration failed: key=\(key.carbonKeyCode) mods=\(modifiers.carbonFlags) err=\(status)")
            return
        }
        print("[CopyCapsule] HotKey registered: key=\(key.carbonKeyCode) mods=\(modifiers.carbonFlags)")

        // Install handler for hotkey press events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        // We need a stable pointer to self for the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        if handlerStatus != noErr {
            print("[CopyCapsule] Failed to install hotkey handler: \(handlerStatus)")
        }
    }

    // MARK: - Unregister

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        actionHandler = nil
    }
}

// MARK: - C Callback

private func hotKeyCallback(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

    // Carbon callbacks arrive on an arbitrary thread — dispatch to main
    DispatchQueue.main.async {
        manager.actionHandler?()
    }

    return noErr
}

// MARK: - Key & Modifier Types

extension HotKeyManager {
    enum Key {
        case v
        case raw(UInt32)

        var carbonKeyCode: UInt32 {
            switch self {
            case .v:       return UInt32(kVK_ANSI_V)
            case .raw(let c): return c
            }
        }
    }

    struct Modifier: OptionSet {
        let rawValue: UInt32

        static let command = Modifier(rawValue: UInt32(cmdKey))
        static let shift   = Modifier(rawValue: UInt32(shiftKey))
        static let option  = Modifier(rawValue: UInt32(optionKey))
        static let control = Modifier(rawValue: UInt32(controlKey))

        var carbonFlags: UInt32 { rawValue }
    }
}
