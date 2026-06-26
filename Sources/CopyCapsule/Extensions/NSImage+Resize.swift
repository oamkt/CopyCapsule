import AppKit

extension NSImage {
    /// Returns a new image scaled to fit within `maxSize` while preserving aspect ratio.
    /// Returns self if already within bounds.
    func resized(toMaxSize maxSize: NSSize) -> NSImage {
        guard isValid, maxSize.width > 0, maxSize.height > 0 else { return self }

        let currentSize = self.size
        guard currentSize.width > maxSize.width || currentSize.height > maxSize.height else {
            return self
        }

        let ratio = min(
            maxSize.width / currentSize.width,
            maxSize.height / currentSize.height
        )
        let newSize = NSSize(
            width: currentSize.width * ratio,
            height: currentSize.height * ratio
        )

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        self.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: currentSize),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()

        return resized
    }

    /// PNG data representation. Uses CGImage for reliable bitmap capture.
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Convenience: resize to a target height, preserving aspect ratio.
    func resized(toHeight height: CGFloat) -> NSImage {
        guard isValid, height > 0 else { return self }
        let currentSize = self.size
        guard currentSize.height > height else { return self }

        let ratio = height / currentSize.height
        let maxSize = NSSize(
            width: currentSize.width * ratio,
            height: height
        )
        return resized(toMaxSize: maxSize)
    }
}
