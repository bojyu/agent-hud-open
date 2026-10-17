import AppKit
import SwiftUI
import AgentHUDCore

struct DisplayPane: View {
    let settings: SettingsStore
    let store: UsageStore
    let theme: Theme
    /// Which display the panes below are editing. Owned here so the glow preview can show that screen's
    /// mode rather than always the notch. It starts on the display the HUD is shown on (`Settings.hudDisplay`).
    @State private var screen: String

    init(settings: SettingsStore, store: UsageStore, theme: Theme) {
        self.settings = settings
        self.store = store
        self.theme = theme
        let shown = IslandController.shownScreens(NSScreen.screens, choice: settings.settings.hudDisplay).first
        _screen = State(initialValue: shown.map { ScreenIdentity.key(for: $0) } ?? ScreensPane.attached().first?.key ?? "")
    }
    /// Reduce Transparency and macOS's own light or dark setting, which a screen's look is resolved from as well as from
    /// its settings, and which SwiftUI does not see there (`SettingsStore.effectiveLook(on:)`). Both are held here so
    /// that the look is resolved again, and every preview below drawn again, as either is switched: macOS's setting too
    /// while the app's Appearance holds this window to its own.
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @State private var systemIsLight = SystemAppearance.isLight

    private var selection: NSScreen? {
        NSScreen.screens.first { ScreenIdentity.key(for: $0) == screen } ?? NSScreen.main
    }

    /// The selected screen's placement as its HUD draws it now, an agent's unsaved style included.
    private var placement: ScreenPlacement {
        guard let selection else { return .default(hasNotch: false) }
        return ScreenIdentity.placement(for: selection, in: settings)
    }

    /// The selected screen's look, which every preview below is drawn in.
    private var look: HUDLook {
        // Read for SwiftUI to draw the panes again when either changes; the look reads both from the Mac itself.
        _ = (reducesTransparency, systemIsLight)
        return settings.effectiveLook(on: screen)
    }

    var body: some View {
        let look = look
        VStack(alignment: .leading, spacing: 28) {
            ScreensPane(settings: settings, store: store, theme: theme, look: look, selected: $screen)
            // Simple mode draws no glow, so its screen has no glow settings to show.
            if placement.mode != .simple {
                // The glow's preview shows the HUD at rest, dark in the row of a hardware notch.
                GlowPane(settings: settings, store: store, theme: theme, placement: placement,
                         metrics: ScreenMetrics(screen: selection), screen: screen,
                         look: settings.restingLook(on: screen))
            }
            // The samples show the panel in the selected screen's look.
            IslandPane(settings: settings, theme: theme, look: look)
            SettingsSection(title: L10n.text("菜单栏", "Menu bar"), theme: theme) {
                SettingsToggleRow(
                    label: L10n.text("显示菜单栏图标", "Show menu bar icon"),
                    subtitle: L10n.text("快速查看用量、刷新数据和打开设置。", "Quick access to usage, refresh and settings."),
                    isOn: settings.binding(\.showMenuBarIcon)
                )
            }
        }
        .onReceive(DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            .receive(on: RunLoop.main)) { _ in
            systemIsLight = SystemAppearance.isLight
        }
    }
}

/// The decorative wallpaper a Settings preview of the HUD stands on, the glow's and the selected screen's. The HUD is
/// previewed in its look as it draws it: a solid one with its fill thinned by the transparency drawn, the wallpaper
/// showing through, and clear or regular Liquid Glass in Liquid Glass, which takes in what is drawn behind it in its own
/// window, the wallpaper painted here. The frosted blur and the material take in only the desktop behind the window, so
/// where glass is frosted, and for the material style, it is previewed with its stand-in, the look's own colour over the
/// wallpaper, thinned with the transparency drawn but never below about a third (`HUDLook.glassStandIn`).
struct SettingsPreview<Content: View>: View {
    @ViewBuilder let content: () -> Content
    /// A snapshot draws every glass as its stand-in, and its preview with it.
    @Environment(\.drawsGlassStandIn) private var drawsStandIn

    var body: some View {
        content()
            .environment(\.drawsGlassStandIn, drawsStandIn || !HUDGlass.isLiquid)
            .environment(\.drawsMaterialStandIn, true)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    Image(nsImage: SettingsPreviewArtwork.wallpaper)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .accessibilityHidden(true)
            // A glow reaches past the box it is previewed in, and the preview sits in front of the rows
            // above it. Left interactive, that overhang silently swallows their clicks: AppKit-backed
            // controls keep working because they are real views, and plain SwiftUI buttons stop responding.
            .allowsHitTesting(false)
    }
}

@MainActor
private enum SettingsPreviewArtwork {
    static let wallpaper = NSImage(contentsOf: AppResources.bundle.url(forResource: "settings-wallpaper", withExtension: "png")!)!
}
