import AppKit
import XCTest
import AgentHUDCore
@testable import AgentHUDDesktop

final class GlowPreparationTests: XCTestCase {
    @MainActor
    func testACancelledWorkerDoesNotRasterizeItsMaterials() async {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let settings = GlowSettings()
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let captured = controller.capturePreparation(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16,
            glow: glow, outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells)
        let images = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return GlowWindowController.render(captured)
        }.value
        XCTAssertNil(images.soft)
        XCTAssertNil(images.shadow)
        XCTAssertNil(images.renderer)
    }

    @MainActor
    func testMatchingPreparationInstallsThePreparedSoftGlowAndShadow() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let settings = GlowSettings()
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells)
        let soft = try XCTUnwrap(prepared.soft)
        let shadow = try XCTUnwrap(prepared.shadow)

        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, prepared: prepared)
        XCTAssertTrue(controller.glowLayer.contents as AnyObject? === soft.image)
        XCTAssertTrue(controller.shadowLayer.contents as AnyObject? === shadow.image)

        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false)
        XCTAssertTrue(controller.glowLayer.contents as AnyObject? === soft.image,
                      "An ordinary refresh must retain the material installed at opening")
        XCTAssertTrue(controller.shadowLayer.contents as AnyObject? === shadow.image)
    }

    @MainActor
    func testPreparationLeavesTheCollapsedWindowLayersAndAnimationUntouched() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        var settings = GlowSettings()
        settings.style = .dots
        settings.effect = .ripple
        let pattern = settings.pattern()
        let glow = settings.geometry(islandWidth: geometry.rect.width, islandHeight: geometry.rect.height, islandRadius: 12)
        controller.update(geometry: geometry, island: geometry.rect, islandRadius: 12, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, pattern: pattern)
        let active = GlowAppearance.resolve(levels: [.ok], paused: false, anyAgentActive: true, glow: settings)
        controller.update(geometry: geometry, island: geometry.rect, islandRadius: 12, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: active, look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, pattern: pattern)
        let soft = try XCTUnwrap(controller.glowLayer.contents) as! CGImage
        let shadow = try XCTUnwrap(controller.shadowLayer.contents) as! CGImage
        let windowFrame = controller.panel.frame
        let visible = controller.panel.isVisible
        let glowFrame = controller.glowLayer.frame
        let shadowFrame = controller.shadowLayer.frame
        let opacity = controller.glowLayer.opacity
        let animationKeys = controller.glowLayer.animationKeys()
        let animating = controller.isAnimating
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let expandedGlow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)

        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: expandedGlow,
            outwardOnly: true, appearance: active, look: .standard, shells: Self.noShells, pattern: pattern)
        XCTAssertNotNil(prepared.renderer)
        XCTAssertEqual(controller.panel.frame, windowFrame)
        XCTAssertEqual(controller.panel.isVisible, visible)
        XCTAssertEqual(controller.glowLayer.frame, glowFrame)
        XCTAssertEqual(controller.shadowLayer.frame, shadowFrame)
        XCTAssertEqual(controller.glowLayer.opacity, opacity)
        XCTAssertEqual(controller.glowLayer.animationKeys(), animationKeys)
        XCTAssertEqual(controller.isAnimating, animating)
        XCTAssertTrue(controller.glowLayer.contents as AnyObject? === soft)
        XCTAssertTrue(controller.shadowLayer.contents as AnyObject? === shadow)
    }

    @MainActor
    func testChangedColoursRejectPreparedGlowAndRetainMatchingShadow() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let settings = GlowSettings()
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let green = GlowAppearance.resolve(levels: [.ok], paused: false, anyAgentActive: true, glow: settings)
        let red = GlowAppearance.resolve(levels: [.critical], paused: false, anyAgentActive: true, glow: settings)
        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: green, look: .standard, shells: Self.noShells)
        let soft = try XCTUnwrap(prepared.soft)
        let shadow = try XCTUnwrap(prepared.shadow)

        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: red, look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, prepared: prepared)
        let actual = try XCTUnwrap(controller.glowLayer.contents) as! CGImage
        let expected = try XCTUnwrap(GlowRenderer.render(glow: glow, islandSize: island.size, islandRadius: 26,
            outwardOnly: true, cutout: nil, stops: red.stops, scale: geometry.backingScale))
        XCTAssertFalse(actual === soft.image)
        XCTAssertEqual(try pixels(actual), try pixels(expected.image), "Opening must use the current quota colours")
        XCTAssertTrue(controller.shadowLayer.contents as AnyObject? === shadow.image)
    }

    @MainActor
    func testChangedSizeRejectsBothPreparedImages() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let settings = GlowSettings()
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells)
        let taller = geometry.expandedFrame(size: CGSize(width: 240, height: 150))
        let tallerGlow = settings.geometry(islandWidth: taller.width, islandHeight: taller.height, islandRadius: 26)

        controller.update(geometry: geometry, island: taller, islandRadius: 26, islandFlare: 16, glow: tallerGlow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, prepared: prepared)
        let soft = try XCTUnwrap(controller.glowLayer.contents) as! CGImage
        let shadow = try XCTUnwrap(controller.shadowLayer.contents) as! CGImage
        XCTAssertFalse(soft === (try XCTUnwrap(prepared.soft)).image)
        XCTAssertFalse(shadow === (try XCTUnwrap(prepared.shadow)).image)
        XCTAssertEqual(shadow.height, Int((taller.height + 90) * geometry.backingScale))
    }

    @MainActor
    func testGridPreparationReusesTheRestingImageAndRejectsChangedPattern() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        var settings = GlowSettings()
        settings.style = .dots
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells, pattern: settings.pattern())
        let resting = try XCTUnwrap(prepared.resting)
        XCTAssertNotNil(prepared.renderer)

        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, pattern: settings.pattern(), prepared: prepared)
        XCTAssertTrue(controller.glowLayer.contents as AnyObject? === resting.image)
        settings.gridDensity = 1.5
        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
            animated: false, animatesShells: false, pattern: settings.pattern(), prepared: prepared)
        XCTAssertFalse(controller.glowLayer.contents as AnyObject? === resting.image)
    }

    @MainActor
    func testSoftEffectPreparationKeepsItsSetupWithoutStartingAnAnimation() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        var settings = GlowSettings()
        settings.effect = .flow
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let active = GlowAppearance.resolve(levels: [.ok], paused: false, anyAgentActive: true, glow: settings)
        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: active, look: .standard, shells: Self.noShells, pattern: settings.pattern())
        let renderer = try XCTUnwrap(prepared.renderer)
        let first = try XCTUnwrap(renderer.render(time: 0, blend: 0, breathSeconds: 3, breathAmplitude: 0.6))
        let later = try XCTUnwrap(renderer.render(time: 1, blend: 0, breathSeconds: 3, breathAmplitude: 0.6))
        XCTAssertTrue(first.image === later.image, "The dynamic renderer retains its prepared resting bitmap")
        XCTAssertFalse(controller.isAnimating)
        XCTAssertFalse(controller.panel.isVisible)
        XCTAssertNil(controller.glowLayer.contents)
        XCTAssertNil(controller.shadowLayer.contents)
    }

    @MainActor
    func testFourEdgeDockPreparationUsesTheSameCanonicalCoreAsOpening() throws {
        _ = NSApplication.shared
        for edge in HUDEdge.allCases {
            let geometry = geometry(edge: edge, mode: .logos)
            let controller = GlowWindowController(geometry: geometry)
            defer { controller.close() }
            let flare = NotchGeometry.expandedTopRadius
            let horizontal = edge.isHorizontal
            let card = geometry.expandedFrame(size: CGSize(width: 240 + (horizontal ? flare * 2 : 0),
                                                           height: 120 + (horizontal ? 0 : flare * 2)))
            let island = card.insetBy(dx: horizontal ? flare : 0, dy: horizontal ? 0 : flare)
            let local = GlowWindowController.canonicalIslandFrame(island,
                panel: GlowWindowController.panelFrame(for: geometry), edge: edge)
            XCTAssertEqual(island.size, CGSize(width: 240, height: 120), "\(edge): materials use the card core")
            XCTAssertEqual(local.size, horizontal ? island.size : CGSize(width: island.height, height: island.width))
            let settings = GlowSettings()
            let glow = settings.geometry(islandWidth: local.width, islandHeight: local.height, islandRadius: 26)
            let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
                outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells)

            controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
                outwardOnly: true, appearance: .idle(), look: .standard, shells: Self.noShells,
                animated: true, animatesShells: true, prepared: prepared)
            let shadow = try XCTUnwrap(prepared.shadow)
            XCTAssertEqual(shadow.image.width, Int((local.width + 90) * geometry.backingScale))
            XCTAssertEqual(shadow.image.height, Int((local.height + 90) * geometry.backingScale))
            XCTAssertTrue(controller.shadowLayer.contents as AnyObject? === shadow.image,
                          "\(edge): opening reuses the prepared shadow bitmap")
            XCTAssertTrue(controller.glowLayer.contents as AnyObject? === (try XCTUnwrap(prepared.soft)).image)
        }
    }

    /// The standard look gives no shell a shadow of its own.
    static let noShells = HUDShells(surface: nil, dock: nil)

    @MainActor
    func testALookChangeRejectsThePreparedMaterialsItChanges() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let glow = GlowSettings().geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let shells = HUDShells(surface: HUDShell(frame: island, radius: 26, flare: 16, floats: false, bare: false), dock: nil)
        func capture(_ look: HUDLook) -> GlowWindowController.PreparationInputs {
            controller.capturePreparation(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
                outwardOnly: true, appearance: .idle(), look: look, shells: shells)
        }
        let prepared = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: shells)
        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: shells,
            animated: false, animatesShells: false, prepared: prepared)
        XCTAssertNotNil(controller.installedPreparation(matching: capture(.standard)))
        XCTAssertNil(controller.installedPreparation(matching: capture(HUDLook(appearance: .light))),
                     "A light look's shell casts a shadow of its own")
        XCTAssertNil(controller.installedPreparation(matching: capture(HUDLook(appearance: .dark, material: .glass))),
                     "Glass has the island cut out of the glow")
    }

    @MainActor
    func testTheStandardLookKeepsItsOneShadowUnderTheGlow() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let glow = GlowSettings().geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let shells = HUDShells(surface: HUDShell(frame: island, radius: 26, flare: 16, floats: false, bare: false), dock: nil)
        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: .standard, shells: shells, animated: false, animatesShells: false)
        XCTAssertNotNil(controller.shadowLayer.contents)
        XCTAssertEqual(controller.shadowLayer.opacity, 1)
        XCTAssertNil(controller.shellShadowLayer.contents, "The standard look draws no shell shadow")
        XCTAssertEqual(controller.shellShadowLayer.opacity, 0)
        XCTAssertEqual(controller.dockShadowLayer.opacity, 0)

        controller.update(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(hidden: true), look: .standard, shells: shells,
            animated: false, animatesShells: false)
        XCTAssertFalse(controller.panel.isVisible, "Without its glow the standard HUD shows nothing here")
    }

    @MainActor
    func testALightLookGivesTheShellsShadowsEvenWithoutTheGlow() throws {
        _ = NSApplication.shared
        let geometry = geometry(edge: .top, mode: .simple)
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let card = CGRect(x: geometry.rect.midX - 120, y: geometry.rect.minY - 126, width: 240, height: 120)
        let panel = geometry.rect.insetBy(dx: 0, dy: 2)
        let shells = HUDShells(surface: HUDShell(frame: card, radius: 22, flare: 0, floats: true, bare: false),
                               dock: HUDShell(frame: panel, radius: 10, flare: 0, floats: true, bare: false))
        let glow = GlowSettings().geometry(islandWidth: panel.width, islandHeight: 2, islandRadius: 0)
        let light = HUDLook(appearance: .light)
        controller.update(geometry: geometry, island: panel, islandRadius: 0, islandFlare: 0, glow: glow,
            outwardOnly: true, appearance: .idle(hidden: true), look: light, shells: shells,
            animated: false, animatesShells: false, drawsGlow: false)
        XCTAssertTrue(controller.panel.isVisible, "A light HUD keeps its shadows when the glow is hidden")
        XCTAssertNotNil(controller.shellShadowLayer.contents)
        XCTAssertNotNil(controller.dockShadowLayer.contents)
        XCTAssertEqual(controller.shellShadowLayer.opacity, 1)
        XCTAssertEqual(controller.dockShadowLayer.opacity, 1)
        XCTAssertEqual(controller.shadowLayer.opacity, 0, "The panel's own shadow gives way to the shells'")
        XCTAssertTrue(controller.glowLayer.isHidden)

        // The card goes: its shadow goes with it, and the Simple panel's stays.
        controller.update(geometry: geometry, island: panel, islandRadius: 0, islandFlare: 0, glow: glow,
            outwardOnly: true, appearance: .idle(hidden: true), look: light,
            shells: HUDShells(surface: nil, dock: shells.dock), animated: false, animatesShells: false, drawsGlow: false)
        XCTAssertEqual(controller.shellShadowLayer.opacity, 0)
        XCTAssertEqual(controller.dockShadowLayer.opacity, 1)
    }

    /// A detached card's shadow, held back until the card has grown out of its dock (`ScreenHUD`), fades in once it is
    /// given, and the dock's, which glass shows through the card and which the card cuts from then on, fades to its new
    /// cut with it rather than switch at once beside it. Given at once, as under Reduce Motion, neither fades.
    @MainActor
    func testARevealedCardsShadowAndTheDocksNewCutFadeInTogether() throws {
        _ = NSApplication.shared
        let geometry = geometry(edge: .top, mode: .simple)
        let panel = geometry.rect.insetBy(dx: 0, dy: 2)
        let card = CGRect(x: geometry.rect.midX - 60, y: geometry.rect.minY - 32, width: 120, height: 26)
        let dock = HUDShell(frame: panel, radius: 10, flare: 0, floats: true, bare: false)
        let shells = HUDShells(surface: HUDShell(frame: card, radius: 13, flare: 0, floats: true, bare: false), dock: dock)
        let glow = GlowSettings().geometry(islandWidth: panel.width, islandHeight: 2, islandRadius: 0)
        let glass = HUDLook(appearance: .dark, material: .glass, transparency: 0.5)
        for animates in [true, false] {
            let controller = GlowWindowController(geometry: geometry)
            defer { controller.close() }
            controller.update(geometry: geometry, island: panel, islandRadius: 0, islandFlare: 0, glow: glow,
                outwardOnly: true, appearance: .idle(hidden: true), look: glass,
                shells: HUDShells(surface: nil, dock: dock), animated: false, animatesShells: true, drawsGlow: false)
            let uncut = controller.dockShadowLayer.contents as AnyObject?
            XCTAssertNotNil(uncut)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            controller.dockShadowLayer.removeAllAnimations()
            controller.shellShadowLayer.removeAllAnimations()

            controller.updateShells(shells, look: glass, geometry: geometry, animates: animates)
            XCTAssertFalse(controller.dockShadowLayer.contents as AnyObject? === uncut, "the card cuts the dock's shadow now")
            XCTAssertEqual(controller.shellShadowLayer.opacity, 1)
            let fade = controller.dockShadowLayer.animation(forKey: kCATransition) as? CATransition
            if animates {
                XCTAssertNotNil(controller.shellShadowLayer.animation(forKey: "opacity"), "the card's shadow fades in")
                XCTAssertEqual(fade?.type, .fade, "and the dock's new cut fades in with it")
                XCTAssertEqual(fade?.duration, IslandAnimation.duration)
            } else {
                XCTAssertNil(controller.shellShadowLayer.animation(forKey: "opacity"), "at once")
                XCTAssertNil(fade, "at once")
            }
        }
    }

    /// A detached card that goes back into its dock drops its shadow at once: cut out where the card was, the shadow
    /// fading there would show that place round the shrinking card. That holds when the card goes while the materials
    /// are pending too, once they have come. Any other surface's shadow that goes, the island's grown for an event from
    /// an agent with no mark, still fades out where it was.
    @MainActor
    func testOnlyADetachedCardThatLeavesDropsItsShadowAtOnce() throws {
        _ = NSApplication.shared
        let geometry = geometry(edge: .top, mode: .simple)
        let panel = geometry.rect.insetBy(dx: 0, dy: 2)
        let card = CGRect(x: geometry.rect.midX - 120, y: geometry.rect.minY - 126, width: 240, height: 120)
        let surface = HUDShell(frame: card, radius: 22, flare: 0, floats: true, bare: false)
        let dock = HUDShell(frame: panel, radius: 10, flare: 0, floats: true, bare: false)
        let glow = GlowSettings().geometry(islandWidth: panel.width, islandHeight: 2, islandRadius: 0)
        let light = HUDLook(appearance: .light)
        for (cardLeaves, pending) in [(false, false), (true, false), (true, true)] {
            let name = cardLeaves ? (pending ? "a card leaving while the materials are pending" : "a card leaving")
                : "any other surface"
            let controller = GlowWindowController(geometry: geometry)
            defer { controller.close() }
            func update(surface: HUDShell?, cardLeaves: Bool = false, pending: Bool = false) {
                controller.update(geometry: geometry, island: panel, islandRadius: 0, islandFlare: 0, glow: glow,
                    outwardOnly: true, appearance: .idle(hidden: true), look: light,
                    shells: HUDShells(surface: surface, dock: dock), animated: false, animatesShells: true,
                    cardLeaves: cardLeaves, drawsGlow: false, materialsPending: pending)
            }
            update(surface: surface)
            XCTAssertEqual(controller.shellShadowLayer.opacity, 1, name)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            controller.shellShadowLayer.removeAllAnimations()

            update(surface: nil, cardLeaves: cardLeaves, pending: pending)
            if pending {
                XCTAssertTrue(controller.shellShadowLayer.isHidden, name)
                update(surface: nil)
            }
            XCTAssertFalse(controller.shellShadowLayer.isHidden, name)
            XCTAssertEqual(controller.shellShadowLayer.opacity, 0, name)
            if cardLeaves {
                XCTAssertNil(controller.shellShadowLayer.animation(forKey: "opacity"), "\(name): at once")
            } else {
                XCTAssertNotNil(controller.shellShadowLayer.animation(forKey: "opacity"), "\(name): fades out")
            }
            XCTAssertEqual(controller.dockShadowLayer.opacity, 1, "\(name): the dock keeps its shadow")
        }
    }

    /// A detached card whose shadow shows takes it to another mark, where the shadow follows the card; the dock's, cut
    /// by the card under glass, cannot, so it fades to the card's new place as the card goes there rather than switch
    /// there ahead of it. That holds when the card moves while the materials are pending too, once they have come. Any
    /// other change of the dock's shadow, a card that does not slide, switches at once as before.
    @MainActor
    func testTheDocksCutFadesAfterAShownCardThatSlides() throws {
        _ = NSApplication.shared
        let geometry = geometry(edge: .top, mode: .simple)
        let panel = geometry.rect.insetBy(dx: 0, dy: 2)
        let dock = HUDShell(frame: panel, radius: 10, flare: 0, floats: true, bare: false)
        func line(at x: CGFloat) -> HUDShell {
            HUDShell(frame: CGRect(x: x, y: geometry.rect.minY - 32, width: 120, height: 26), radius: 13, flare: 0,
                     floats: true, bare: false)
        }
        let glow = GlowSettings().geometry(islandWidth: panel.width, islandHeight: 2, islandRadius: 0)
        let glass = HUDLook(appearance: .dark, material: .glass, transparency: 0.5)
        for (slides, pending) in [(true, false), (true, true), (false, false)] {
            let name = slides ? (pending ? "a card sliding while the materials are pending" : "a card sliding")
                : "a card that does not slide"
            let controller = GlowWindowController(geometry: geometry)
            defer { controller.close() }
            func update(surface: HUDShell, fadesDock: Bool = false, pending: Bool = false) {
                controller.update(geometry: geometry, island: panel, islandRadius: 0, islandFlare: 0, glow: glow,
                    outwardOnly: true, appearance: .idle(hidden: true), look: glass,
                    shells: HUDShells(surface: surface, dock: dock), animated: false, animatesShells: true,
                    fadesDock: fadesDock, drawsGlow: false, materialsPending: pending)
            }
            update(surface: line(at: panel.minX + 20))
            let before = controller.dockShadowLayer.contents as AnyObject?
            XCTAssertNotNil(before, name)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            controller.dockShadowLayer.removeAllAnimations()

            let there = line(at: panel.maxX - 140)
            update(surface: there, fadesDock: slides, pending: pending)
            if pending { update(surface: there) }
            XCTAssertFalse(controller.dockShadowLayer.contents as AnyObject? === before,
                           "\(name): the dock's shadow is cut where the card is now")
            let fade = controller.dockShadowLayer.animation(forKey: kCATransition) as? CATransition
            if slides {
                XCTAssertEqual(fade?.type, .fade, "\(name): the new cut fades in")
                XCTAssertEqual(fade?.duration, IslandAnimation.duration, name)
            } else {
                XCTAssertNil(fade, "\(name): at once")
            }
        }
    }

    /// A change of look keeps the old look's materials up while the new ones are drawn, so that the new fade in over
    /// them. One that also turns the canvas, as a drop that changes the mode does, hides them as any pending surface
    /// does, rather than show a glow laid out along the top turned onto a side.
    @MainActor
    func testAChangeOfLookKeepsTheOldMaterialsOnlyWhereTheyWereLaidOut() throws {
        _ = NSApplication.shared
        let top = geometry(edge: .top, mode: .logos)
        let controller = GlowWindowController(geometry: top)
        defer { controller.close() }
        func update(_ geometry: NotchGeometry, look: HUDLook, pending: Bool) {
            let island = geometry.rect
            let glow = GlowSettings().geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 10)
            controller.update(geometry: geometry, island: island, islandRadius: 10, islandFlare: 0, glow: glow,
                outwardOnly: true, appearance: .idle(), look: look, shells: HUDShells(surface: nil, dock: nil),
                animated: false, animatesShells: false, materialsPending: pending)
        }
        update(top, look: .standard, pending: false)
        update(top, look: HUDLook(appearance: .light), pending: true)
        XCTAssertFalse(controller.glowLayer.isHidden, "the old look's glow stays until the new one fades in over it")
        update(top, look: HUDLook(appearance: .light), pending: false)
        update(geometry(edge: .left, mode: .logos), look: HUDLook(appearance: .dark, material: .glass), pending: true)
        XCTAssertTrue(controller.glowLayer.isHidden, "a glow laid out along the top is not shown turned onto a side")
        XCTAssertTrue(controller.shellShadowLayer.isHidden)
    }

    @MainActor
    func testAShellShadowFallsDownTheScreenFromEveryEdge() throws {
        _ = NSApplication.shared
        for edge in HUDEdge.allCases {
            let geometry = geometry(edge: edge, mode: .simple)
            let controller = GlowWindowController(geometry: geometry)
            defer { controller.close() }
            let panel = geometry.rect
            let glow = GlowSettings().geometry(islandWidth: 2, islandHeight: 2, islandRadius: 0)
            controller.update(geometry: geometry, island: panel, islandRadius: 0, islandFlare: 0, glow: glow,
                outwardOnly: true, appearance: .idle(), look: HUDLook(appearance: .light),
                shells: HUDShells(surface: HUDShell(frame: panel, radius: 10, flare: 0, floats: true, bare: false), dock: nil),
                animated: false, animatesShells: false, drawsGlow: false)
            let host = try XCTUnwrap(controller.panel.contentView)
            let shadow = controller.shellShadowLayer.convert(controller.shellShadowLayer.bounds, to: host.layer)
            let local = panel.offsetBy(dx: -controller.panel.frame.minX, dy: -controller.panel.frame.minY)
            XCTAssertEqual(shadow.midX, local.midX, accuracy: 0.01, "\(edge): the shadow stays under the panel")
            XCTAssertEqual(shadow.midY, local.midY - GlowRenderer.shellShadowDrop, accuracy: 0.01,
                           "\(edge): and falls down the screen")
        }
    }

    @MainActor
    func testAGlassIslandIsCutOutOfThePreparedGlowAndShadow() throws {
        _ = NSApplication.shared
        let geometry = geometry()
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let island = geometry.expandedFrame(size: CGSize(width: 240, height: 120))
        let glow = GlowSettings().geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 26)
        let shells = HUDShells(surface: HUDShell(frame: island, radius: 26, flare: 16, floats: false, bare: false), dock: nil)
        let glass = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: HUDLook(appearance: .dark, material: .glass), shells: shells)
        let solid = controller.prepare(geometry: geometry, island: island, islandRadius: 26, islandFlare: 16, glow: glow,
            outwardOnly: true, appearance: .idle(), look: HUDLook(appearance: .light), shells: shells)
        let soft = try XCTUnwrap(glass.soft), filled = try XCTUnwrap(solid.soft)
        // The island's middle, a point below its foot and one inside a flare, in points from the bitmap's lower left.
        let middle = CGPoint(x: soft.padding + glow.sideInset + island.width / 2, y: soft.padding + glow.sideInset + island.height / 2)
        let below = CGPoint(x: middle.x, y: soft.padding + glow.sideInset / 2)
        // Spelled out step by step: Xcode 16.4's Swift finds the one-line sums of CGFloat and Double ambiguous.
        let corner: CGFloat = soft.padding + glow.sideInset
        let flare = CGPoint(x: corner - 2, y: corner + island.height - 2)
        XCTAssertEqual(try alpha(of: soft, at: middle), 0, "Glass shows no glow under the island")
        XCTAssertEqual(try alpha(of: soft, at: flare), 0, "nor under its flares")
        XCTAssertGreaterThan(try alpha(of: filled, at: middle), 0, "A solid island hides the glow it covers")
        XCTAssertEqual(try alpha(of: soft, at: below), try alpha(of: filled, at: below), "The glow round the island is unchanged")

        let shadow = try XCTUnwrap(glass.shadow), cast = try XCTUnwrap(solid.shadow)
        let core = CGPoint(x: shadow.padding + island.width / 2,
                           y: shadow.padding + island.height / 2 + GlowRenderer.shellShadowDrop)
        XCTAssertEqual(try alpha(of: shadow, at: core), 0, "Glass shows no shadow through itself")
        XCTAssertGreaterThan(try alpha(of: cast, at: core), 0, "A light solid shell covers its shadow itself")
        let beneath = CGPoint(x: core.x, y: shadow.padding - 4)
        XCTAssertGreaterThan(try alpha(of: shadow, at: beneath), 0, "and keeps the shadow round it")
    }

    func testAGlassGridFrameLeavesTheIslandAndItsFlaresEmpty() throws {
        var settings = GlowSettings()
        settings.style = .blocks
        let island = CGSize(width: 240, height: 40)
        let glow = settings.geometry(islandWidth: island.width, islandHeight: island.height, islandRadius: 12)
        let key = GlowFrameRenderer.Key(glow: glow, islandRadius: 12, stops: GlowGradient.idleStops, scale: 2,
                                        pattern: settings.pattern(), cutout: GlowCutout(flare: 8))
        let frame = try XCTUnwrap(GlowFrameRenderer.resting(key))
        for x: CGFloat in [glow.sideInset - 2, glow.sideInset + 1, glow.sideInset + island.width / 2,
                           glow.sideInset + island.width - 1, glow.sideInset + island.width + 2] {
            XCTAssertEqual(try alpha(of: frame, at: CGPoint(x: x, y: glow.height - 1)), 0, "at \(x)")
        }
    }

    func testShellShapesFollowTheIslandsOwn() {
        let grown = ShellShape(size: CGSize(width: 200, height: 40), radius: 12, flare: 8, floats: false)
            .path(at: CGPoint(x: 10, y: 10)).boundingBoxOfPath
        let path = ShellShape(size: CGSize(width: 200, height: 40), radius: 12, flare: 8, floats: false)
            .path(at: CGPoint(x: 10, y: 10))
        for (actual, expected) in zip([grown.minX, grown.minY, grown.maxX, grown.maxY], [2, 10, 218, 50] as [CGFloat]) {
            XCTAssertEqual(actual, expected, accuracy: 0.01, "The flares widen the shape along the edge above")
        }
        XCTAssertTrue(path.contains(CGPoint(x: 9, y: 49)), "A flare fills the corner beside the core at the edge")
        XCTAssertFalse(path.contains(CGPoint(x: 3, y: 42)), "and curves away from it lower down")
        XCTAssertFalse(path.contains(CGPoint(x: 11, y: 11)), "The corners away from the edge are round")
        let floating = ShellShape(size: CGSize(width: 120, height: 30), radius: 15, flare: 0, floats: true)
            .path(at: .zero)
        let bounds = floating.boundingBoxOfPath
        for (actual, expected) in zip([bounds.minX, bounds.minY, bounds.maxX, bounds.maxY], [0, 0, 120, 30] as [CGFloat]) {
            XCTAssertEqual(actual, expected, accuracy: 0.01)
        }
        XCTAssertFalse(floating.contains(CGPoint(x: 1, y: 29)), "A floating shape rounds the corners at the edge too")
    }

    func testOnlyGlassCutsTheIslandOutOfTheGlow() {
        XCTAssertNil(GlowCutout(look: .standard, flare: 8))
        XCTAssertNil(GlowCutout(look: HUDLook(appearance: .light), flare: 8))
        XCTAssertEqual(GlowCutout(look: HUDLook(appearance: .light, material: .glass), flare: 8), GlowCutout(flare: 8))
        XCTAssertFalse(HUDLook.standard.castsShellShadows)
        XCTAssertTrue(HUDLook(appearance: .light).castsShellShadows)
        XCTAssertTrue(HUDLook(appearance: .dark, material: .glass).castsShellShadows)
    }

    @MainActor
    func testDetachedCardsAreAsRoundAsTheIslandDrawsThem() {
        XCTAssertEqual(ScreenHUD.detachedRadius(height: 300, full: true, bubble: false), 22)
        XCTAssertEqual(ScreenHUD.detachedRadius(height: 60, full: false, bubble: true), 14)
        XCTAssertEqual(ScreenHUD.detachedRadius(height: 26, full: false, bubble: false), 13, "A line is a capsule")
        XCTAssertEqual(ScreenHUD.detachedRadius(height: 20, full: true, bubble: false), 10)
    }

    @MainActor
    func testSimpleModeOrdersGlowWindowOutUnderStandardLook() {
        _ = NSApplication.shared
        let geometry = geometry(edge: .right, mode: .simple)
        let controller = GlowWindowController(geometry: geometry)
        defer { controller.close() }
        let panel = geometry.rect
        let glow = GlowSettings().geometry(islandWidth: 2, islandHeight: 2, islandRadius: 0)
        let shells = HUDShells(
            surface: HUDShell(frame: panel, radius: 14, flare: 0, floats: true, bare: false),
            dock: nil
        )
        let prepared = controller.prepare(
            geometry: geometry, island: panel, islandRadius: 14, islandFlare: 0,
            glow: glow, outwardOnly: true, appearance: .idle(), look: .standard, shells: shells, drawsGlow: false
        )
        XCTAssertNil(prepared.soft)
        XCTAssertNil(prepared.shadow)

        controller.update(
            geometry: geometry, island: panel, islandRadius: 14, islandFlare: 0,
            glow: glow, outwardOnly: true, appearance: .idle(), look: .standard, shells: shells,
            animated: false, animatesShells: false, drawsGlow: false,
            prepared: prepared
        )
        XCTAssertFalse(controller.panel.isVisible,
                       "A Simple HUD under the standard look draws neither glow nor shell shadow, so the overlay window stays ordered out")
    }

    /// The alpha at `point`, in points from the image's lower-left corner.
    private func alpha(of image: GlowImage, at point: CGPoint) throws -> UInt8 {
        let cg = image.image
        let scale = CGFloat(cg.width) / image.size.width
        let x = Int(point.x * scale), y = cg.height - 1 - Int(point.y * scale)
        guard let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cropped = cg.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
            throw XCTSkip("could not read the bitmap")
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self)[3])
    }

    private func geometry(edge: HUDEdge = .top, mode: HUDMode? = nil) -> NotchGeometry {
        let screen = CGRect(x: -20000, y: -20000, width: 1000, height: 800)
        let queue = edge.isHorizontal ? CGSize(width: 200, height: 24) : CGSize(width: 24, height: 200)
        let rect = NotchGeometry.stripRect(queue: queue, frame: screen,
                                          placement: ScreenPlacement(edge: edge))
        return NotchGeometry(screenFrame: screen, mode: mode ?? (edge == .top ? .notch : .logos), edge: edge, hasNotch: false,
            rect: rect,
            cornerRadius: 12, backingScale: 2, menuBarHeight: 24)
    }

    private func pixels(_ image: CGImage) throws -> Data {
        try XCTUnwrap(image.dataProvider?.data) as Data
    }
}
