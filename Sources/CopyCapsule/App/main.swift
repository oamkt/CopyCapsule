import AppKit

// Traditional entry point — AppDelegate handles the rest.
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
