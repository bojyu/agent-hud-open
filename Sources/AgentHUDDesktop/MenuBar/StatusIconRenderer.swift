import AppKit
import AgentHUDCore

/// The menu bar mark: a thin gauge ring in the menu bar's own label colour, as the system's extras are drawn, whose arc
/// is the highest share used. The arc turns orange at a warning and red at a critical level, so colour only appears
/// when it says something; a paused or locked HUD shows the faint track alone, dashed.
enum StatusIconRenderer {
    static let size = NSSize(width: 16, height: 16)
    static let lineWidth: CGFloat = 2

    /// - usedPct: the highest share used, 0…100; nil before any reading.
    /// - level: that reading's level, which colours the arc.
    /// - idle: paused or without access: the track alone, dashed.
    static func image(usedPct: Double?, level: StatusLevel?, idle: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let ring = rect.insetBy(dx: lineWidth / 2 + 0.75, dy: lineWidth / 2 + 0.75)
            let center = CGPoint(x: ring.midX, y: ring.midY)
            let radius = ring.width / 2

            // Track. Colours resolve at draw time, so they follow the menu bar's light or dark look.
            let track = NSBezierPath(ovalIn: ring)
            track.lineWidth = lineWidth
            if idle {
                track.setLineDash([1.6, 2.2], count: 2, phase: 0)
                NSColor.labelColor.withAlphaComponent(0.55).setStroke()
                track.stroke()
                return true
            }
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()

            // Arc: clockwise from twelve o'clock, round-capped.
            let fraction = max(0, min(1, (usedPct ?? 0) / 100))
            if fraction > 0 {
                let arc = NSBezierPath()
                if fraction >= 0.999 {
                    arc.appendOval(in: ring)
                } else {
                    arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                                  endAngle: 90 - 360 * fraction, clockwise: true)
                }
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                arcColor(level).setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = AppResources.applicationName
        return image
    }

    static func arcColor(_ level: StatusLevel?) -> NSColor {
        switch level {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .ok, nil: return .labelColor
        }
    }
}
