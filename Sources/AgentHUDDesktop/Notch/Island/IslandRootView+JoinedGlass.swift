import SwiftUI
import AgentHUDCore

/// The Simple panel's glass joined with its hover line's: on a dock that separates its agents, in a look that is Liquid
/// Glass here, the panel and the line are one piece of Liquid Glass (`JoinedGlass`) instead of a surface each.
extension IslandRootView {
    /// The card on show is the Simple panel's one-line peek.
    var growsFromPanel: Bool {
        isOpen && !pinned && alert == nil && peek?.style == .line && simpleMeter != nil && !showsAlertDetails
    }

    /// The Simple panel's own place inside the window: its strip without the margin on the parked side.
    var simplePanelRect: CGRect? {
        guard simpleMeter != nil, var panel = logoQueueFrame else { return nil }
        let margin = SimpleMeterConfig.edgeMargin
        switch edge {
        case .top: panel.origin.y += margin; panel.size.height -= margin
        case .bottom: panel.size.height -= margin
        case .left: panel.origin.x += margin; panel.size.width -= margin
        case .right: panel.size.width -= margin
        }
        return panel
    }

    /// The Simple panel's own shape inside the window.
    private var simplePanelPath: Path? {
        guard let simpleMeter, let panel = simplePanelRect else { return nil }
        return Path(roundedRect: panel, cornerRadius: simpleMeter.cornerRadius, style: .continuous)
    }

    /// Everything in `bounds` but the Simple panel, which what grows out of it is cut by; everything where there is none.
    @ViewBuilder
    func outsidePanel(_ bounds: CGSize) -> some View {
        if separatesAgents, let panel = simplePanelPath {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: bounds))
                path.addPath(panel)
            }.fill(style: FillStyle(eoFill: true))
        } else {
            Rectangle()
        }
    }

    /// Whether the Simple panel's glass is drawn with the line's, as one piece of Liquid Glass (`joinedGlass`), rather
    /// than each by a surface of its own: on a dock that separates its agents, while the panel stands beside its card or
    /// alone, in a look that is Liquid Glass here (`HUDLook.drawsLiquidGlass(standIn:liquid:)`). Solid, the material,
    /// frosted glass and glass's stand-in, in a picture or a recording, draw as they always have.
    /// - liquid: whether glass is Liquid Glass here (`HUDGlass.isLiquid`), which a test sets both ways on any Mac.
    func joinsPanelGlass(standIn: Bool, liquid: Bool = HUDGlass.isLiquid) -> Bool {
        let visible = isOpen || alert != nil
        return separatesAgents && simplePanelRect != nil && look.drawsLiquidGlass(standIn: standIn, liquid: liquid)
            && (detached || !visible) && (alert == nil || focusVendor != nil)
    }

    /// Whether the card's glass is drawn with the panel's: only while it is the line. A full card, a reminder or a
    /// request keeps its own surface, a piece apart from the panel's, 6 points off it.
    func cardJoinsPanel(standIn: Bool, liquid: Bool = HUDGlass.isLiquid) -> Bool {
        joinsPanelGlass(standIn: standIn, liquid: liquid) && growsFromPanel
    }

    /// The Simple panel's glass and the line's as one piece of Liquid Glass (`JoinedGlass`), with the look's dimming
    /// beneath them, which the glass blurs with the desktop. The panel's glass stays where the panel is, as its figures
    /// do. The card's two pieces follow the card exactly: its frame and corner, interpolated as `CardPlacement`
    /// interpolates them and keyed to its place on screen, and its way in and out of the dock. They draw only while the
    /// card is the line (`cardJoinsPanel(standIn:liquid:)`); any other card draws its own surface.
    func joinedGlass(panel: CGRect, radius: CGFloat, card: CGRect?, bounds: CGSize) -> some View {
        let joins = cardJoinsPanel(standIn: standsInForGlass)
        let motion = cardMotion
        let tuck = simpleMeter?.tuckOffset ?? .zero
        let isTucked = simpleMeter?.isTucked ?? false
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        func piece(_ card: CGRect, dimming: Color?) -> some View {
            Color.clear
                .modifier(CardPiece(frame: card, radius: detachedRadius(height: card.height), shown: joins,
                                    dimming: dimming, lookAnimation: lookAnimation))
                .animation(motion, value: cardScreenFrame)
                .transition(cardTransition(card, in: bounds, line: joins).animation(motion ?? .easeOut(duration: 0.12)))
        }
        return ZStack(alignment: .topLeading) {
            shape.fill(look.glassDimming)
                .animation(lookAnimation, value: look)
                .frame(width: panel.width, height: panel.height)
                .offset(tuck)
                .animation(motion, value: isTucked)
                .position(x: panel.midX, y: panel.midY)
                .transaction { $0.animation = nil }
            // The line's dimming where it is not under the panel's, so the two never darken each other.
            ZStack(alignment: .topLeading) {
                if let card { piece(card, dimming: look.glassDimming) }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            .mask { outsidePanel(bounds) }
            JoinedGlass(look: look) {
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(width: panel.width, height: panel.height)
                        .hudGlassPiece(in: shape)
                        .offset(tuck)
                        .animation(motion, value: isTucked)
                        .position(x: panel.midX, y: panel.midY)
                        .transaction { $0.animation = nil }
                    if let card { piece(card, dimming: nil) }
                }
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    }

    /// A piece of the card that `joinedGlass` draws, its glass or the dimming beneath it, in the card's shape and place
    /// as `CardPlacement` interpolates them, so the piece and the card never part. Drawn only while `shown`, while the
    /// card is the line; the piece stays meanwhile, so it comes and goes with the card.
    private struct CardPiece: ViewModifier, @preconcurrency Animatable {
        var frame: CGRect
        var radius: CGFloat
        let shown: Bool
        /// The dimming's colour, or nil for the glass.
        let dimming: Color?
        /// How the dimming moves to a new look's colour.
        let lookAnimation: Animation?

        var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>,
                                           CGFloat> {
            get { .init(.init(.init(frame.minX, frame.minY), .init(frame.width, frame.height)), radius) }
            set {
                frame = CGRect(x: newValue.first.first.first, y: newValue.first.first.second,
                               width: newValue.first.second.first, height: newValue.first.second.second)
                radius = newValue.second
            }
        }

        func body(content: Content) -> some View {
            let card = RoundedRectangle(cornerRadius: min(radius, min(frame.width, frame.height) / 2), style: .continuous)
            Group {
                if let dimming {
                    card.fill(dimming).animation(lookAnimation, value: dimming).opacity(shown ? 1 : 0)
                } else {
                    content.hudGlassPiece(in: card, shown: shown)
                }
            }
            // Shown or not at once, as the card's own surface comes and goes (`CardPlacement`).
            .transaction(value: shown) { $0.animation = nil }
            .frame(width: max(0, frame.width), height: max(0, frame.height))
            .position(x: frame.midX, y: frame.midY)
        }
    }
}
