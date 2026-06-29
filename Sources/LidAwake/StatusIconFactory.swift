import AppKit

enum StatusIconFactory {
    static func makeCoderIcon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18))
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.black.setFill()

        NSBezierPath(ovalIn: NSRect(x: 7.8, y: 12.5, width: 4.4, height: 4.4)).fill()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 5.4, y: 9.8))
        body.curve(
            to: NSPoint(x: 14.6, y: 9.8),
            controlPoint1: NSPoint(x: 6.1, y: 12.3),
            controlPoint2: NSPoint(x: 13.9, y: 12.3)
        )
        body.line(to: NSPoint(x: 14.6, y: 8.6))
        body.line(to: NSPoint(x: 5.4, y: 8.6))
        body.close()
        body.fill()

        NSBezierPath(roundedRect: NSRect(x: 3.8, y: 4.7, width: 12.4, height: 6.7), xRadius: 1.1, yRadius: 1.1).fill()

        let base = NSBezierPath()
        base.move(to: NSPoint(x: 2.4, y: 4.7))
        base.line(to: NSPoint(x: 17.6, y: 4.7))
        base.line(to: NSPoint(x: 19, y: 2.7))
        base.line(to: NSPoint(x: 1, y: 2.7))
        base.close()
        base.fill()

        if active {
            NSBezierPath(ovalIn: NSRect(x: 15.8, y: 13.7, width: 3.2, height: 3.2)).fill()
        }

        return image
    }
}
