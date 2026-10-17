import SwiftUI
import QuartzCore
import AgentHUDCore

/// The surface, its glow and the canvas cleanup share one finite transition.
enum IslandAnimation {
    static let duration: TimeInterval = 0.45
    /// A soft start and a long settle, so a panel eases out of its place rather than snapping out of it. SwiftUI's
    /// curve and Core Animation's are the same one, so the window and what it draws move together.
    private static let points: (Double, Double, Double, Double) = (0.32, 0.72, 0, 1)
    static let curve = Animation.timingCurve(points.0, points.1, points.2, points.3, duration: duration)
    static var mediaCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: Float(points.0), Float(points.1), Float(points.2), Float(points.3))
    }

    /// Cross-fades what `layer` draws now into what it is given next, on the island's curve: a change of look in layers
    /// that are drawn for one ground and do not fade with a colour, such as a blur, a dock's marks or a reminder's bot.
    static func fadeLook(of layer: CALayer, duration: TimeInterval = duration) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        fade.timingFunction = mediaCurve
        // A layer keeps one transition, under this key whatever key it is added with.
        layer.add(fade, forKey: kCATransition)
    }

    static func attachmentAlignment(for edge: HUDEdge) -> Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    /// Content enters from its parked edge while the silhouette grows into the screen.
    static func entryOffset(for edge: HUDEdge) -> CGSize {
        switch edge {
        case .top: return CGSize(width: 0, height: -5)
        case .bottom: return CGSize(width: 0, height: 5)
        case .left: return CGSize(width: -5, height: 0)
        case .right: return CGSize(width: 5, height: 0)
        }
    }
}
