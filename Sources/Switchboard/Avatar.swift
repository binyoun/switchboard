import AppKit
import SwitchboardCore

/// Round avatars: the account picture if the browser cached one, otherwise the
/// profile's theme colour with its initial. A small browser badge sits bottom-right.
enum Avatar {
    private static var cache: [String: NSImage] = [:]

    static func clearCache() { cache.removeAll() }

    static func color(_ p: Profile) -> NSColor {
        guard let argb = p.color else { return .systemGray }
        return NSColor(srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
                       green: CGFloat((argb >> 8) & 0xFF) / 255,
                       blue: CGFloat(argb & 0xFF) / 255, alpha: 1)
    }

    static func image(_ p: Profile, size: CGFloat) -> NSImage {
        let key = "\(p.ref)@\(size)"
        if let hit = cache[key] { return hit }

        let picture = p.picture.flatMap { NSImage(contentsOf: $0) }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect)
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            if let picture {
                picture.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                color(p).setFill()
                rect.fill()
                let initial = String(p.name.prefix(1)).uppercased() as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size * 0.5, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
                let s = initial.size(withAttributes: attrs)
                initial.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2),
                             withAttributes: attrs)
            }
            NSGraphicsContext.restoreGraphicsState()

            // Browser badge: a small dot in the browser's colour.
            let d = size * 0.36
            let badge = NSRect(x: rect.maxX - d, y: rect.minY, width: d, height: d)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -1, dy: -1)).fill()
            browserColor(p.browser).setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        cache[key] = img
        return img
    }

    static func browserColor(_ b: Browser) -> NSColor {
        switch b.id {
        case "edge": return NSColor(srgbRed: 0.05, green: 0.47, blue: 0.84, alpha: 1)
        case "chrome": return NSColor(srgbRed: 0.98, green: 0.74, blue: 0.02, alpha: 1)
        default: return .systemGray
        }
    }
}
