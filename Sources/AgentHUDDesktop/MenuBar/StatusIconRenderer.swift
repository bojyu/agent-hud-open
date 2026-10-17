import AppKit
import AgentHUDCore

/// 22×11 notch silhouette, or a 14 pt ring for a copy held to the Simple panel: 1.5 px outline in the label color, filled
/// with the same gradient as the glow.
enum StatusIconRenderer {
    static var size: NSSize { ScreenPlacement.onlyMode == .simple ? NSSize(width: 14, height: 14) : NSSize(width: 22, height: 11) }

    static func image(stops: [GradientStop]) -> NSImage {
        let ring = ScreenPlacement.onlyMode == .simple
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 0.75, dy: 0.75)
            let path = ring ? NSBezierPath(ovalIn: inset) : NSBezierPath(roundedRect: inset, xRadius: 4, yRadius: 4)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            var resolved = stops
            if resolved.count == 1 {
                resolved = [GradientStop(color: stops[0].color, location: 0), GradientStop(color: stops[0].color, location: 1)]
            }
            if !resolved.isEmpty,
               let gradient = NSGradient(colors: resolved.map { NSColor($0.color) }, atLocations: resolved.map { CGFloat($0.location) }, colorSpace: .sRGB) {
                gradient.draw(in: inset, angle: 0)
            }
            NSGraphicsContext.restoreGraphicsState()
            // Resolved at draw time, so it follows the menu bar's light/dark appearance.
            NSColor.labelColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
