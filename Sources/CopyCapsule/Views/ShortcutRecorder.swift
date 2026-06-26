import SwiftUI
import AppKit

/// Shows current shortcut. Click to record a new one.
struct ShortcutRecorder: View {
    let label: String
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void
    @State private var isRecording = false

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Button {
                isRecording = true
            } label: {
                Text(isRecording ? "按下组合键..." : shortcut.displayString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isRecording ? .white : .primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.blue.opacity(0.8) : Color.gray.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .background(KeyCaptureView(isRecording: $isRecording, onCapture: { event in
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                onChange(Shortcut(keyCode: Int(event.keyCode), modifiers: mods.rawValue))
                isRecording = false
            }))
        }
    }
}

/// NSView that captures keyDown when recording.
struct KeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? KeyCaptureNSView {
            v.isRecording = isRecording
            v.onCapture = onCapture
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var view: KeyCaptureNSView?
    }
}

class KeyCaptureNSView: NSView {
    var isRecording = false { didSet { if isRecording { window?.makeFirstResponder(self) } } }
    var onCapture: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if isRecording {
            onCapture?(event)
        }
    }
    override func draw(_ rect: NSRect) {} // invisible
}

/// Shortcut model.
struct Shortcut: Equatable, Codable {
    var keyCode: Int
    var modifiers: UInt

    static let defaultTagInput = Shortcut(keyCode: 5, modifiers: NSEvent.ModifierFlags.command.rawValue)
    static let defaultToggleWindow = Shortcut(keyCode: 9, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)
    static let defaultExport = Shortcut(keyCode: 14, modifiers: NSEvent.ModifierFlags.command.rawValue)

    var displayString: String {
        var parts: [String] = []
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        if f.contains(.command) { parts.append("⌘") }
        if f.contains(.shift)   { parts.append("⇧") }
        if f.contains(.option)  { parts.append("⌥") }
        if f.contains(.control) { parts.append("⌃") }
        let chars: [Int: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",
            8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",
            16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",36:"⏎",49:"␣",53:"⎋"
        ]
        parts.append(chars[keyCode] ?? "\(keyCode)")
        return parts.joined(separator: " + ")
    }

    func matches(event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue == modifiers
    }
}
