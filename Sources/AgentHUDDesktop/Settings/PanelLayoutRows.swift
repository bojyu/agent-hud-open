import SwiftUI
import AgentHUDCore

/// One screen's panel layout, in that screen's part of Settings → Display: whether the screen uses the shared layout or
/// its own, in which state, and what a person can do about it. Reset to Default here gives the screen the default
/// layout and leaves its HUD style, which has a Reset to Default of its own (`ScreenStyleRow`). A screen's versions
/// cover its layout and its HUD style, so Revert to Previous undoes either reset. A click takes effect at once, where an
/// agent's change waits in the panel to be saved.
struct ScreenLayoutRow: View {
    let layout: PanelLayoutStore
    let screen: String

    private var scope: PanelLayoutScope { .screen(screen) }
    /// Whether the screen keeps a layout of its own, saved or as its draft, which Reset to Default is offered for.
    var hasOwn: Bool { layout.ownLayout(of: screen) != nil || layout.draft(of: screen)?.layout != nil }
    /// Whether Reset to Default would change the screen's layout: its own is not the default view, or a draft waits.
    var canReset: Bool { layout.ownLayout(of: screen)?.isDefault != true || layout.draft(of: screen) != nil }

    var body: some View {
        SettingRow(label: L10n.text("面板布局", "Panel layout"), subtitle: status) {
            HStack(spacing: 8) {
                if hasOwn || layout.draft(of: screen) != nil {
                    Button(L10n.text("使用共用布局", "Use Shared Layout")) { layout.useShared(screen) }
                        .accessibilityIdentifier("settings-screen-layout-shared")
                }
                Button(L10n.text("恢复上一版", "Revert to Previous")) { layout.revert(scope) }
                    .disabled(!layout.canRevert(scope))
                    .accessibilityIdentifier("settings-screen-layout-revert")
                if hasOwn {
                    Button(L10n.text("恢复默认", "Reset to Default"), action: reset)
                        .disabled(!canReset)
                        .accessibilityIdentifier("settings-screen-layout-reset")
                }
            }
            .controlSize(.small)
        }
    }

    /// Gives the screen the default view as its own layout, its HUD style as saved.
    func reset() { layout.reset(scope) }

    /// Which layout the screen's panel draws, and in which state, and whether its HUD shows an agent's unsaved style.
    private var status: String {
        var lines = [layoutStatus]
        if layout.hasStyleDraft(screen) {
            lines.append(L10n.text("HUD 正显示 agent 未保存的样式，在这里改动会先丢弃它",
                                   "The HUD shows an agent's unsaved style; a change here drops it first"))
        }
        return lines.joined(separator: "\n")
    }

    /// Which layout the screen's panel draws, and in which state.
    private var layoutStatus: String {
        switch layout.draft(of: screen) {
        case .own?:
            return L10n.text("面板正显示这块屏幕未保存的布局", "The panel shows an unsaved layout for this display")
        case .shared?:
            return L10n.text("面板正显示未保存的改动：改用共用布局", "The panel shows an unsaved change: back to the shared layout")
        case nil:
            break
        }
        if let own = layout.ownLayout(of: screen) {
            return own.isDefault ? L10n.text("这块屏幕自己的布局：默认布局", "Its own layout: the default layout")
                : L10n.text("这块屏幕自己的自定义布局", "Its own custom layout")
        }
        return layout.hasDraft ? L10n.text("使用共用布局，面板正显示它未保存的改动", "Uses the shared layout, which has an unsaved change in the panel")
            : L10n.text("使用共用布局", "Uses the shared layout")
    }
}

/// One screen's HUD style, in that screen's part of Settings → Display: Reset to Default gives it the default placement
/// and glow at once, the HUD's mode, place and sizes, its appearance and material, Dark and Solid, and the glow together,
/// and leaves its panel layout. It is a version of the screen, so the Panel layout row's Revert to Previous undoes it.
struct ScreenStyleRow: View {
    let settings: SettingsStore
    let screen: String

    /// Whether Reset to Default would change what the screen's HUD draws: the screen keeps a placement or a glow of its
    /// own, or an agent's unsaved style shows on it.
    var canReset: Bool {
        settings.settings.screens[screen] != nil || settings.settings.screenGlow[screen] != nil
            || settings.panelLayout.hasStyleDraft(screen)
    }

    var body: some View {
        SettingRow(label: L10n.text("HUD 样式", "HUD style"),
                   subtitle: ScreenPlacement.onlyMode == .simple
                       ? L10n.text("位置、大小和外观一起回到默认；「恢复上一版」可以撤销。",
                                   "Position, sizes and appearance go back to their defaults; Revert to Previous undoes it.")
                       : L10n.text("形态、位置、大小、外观和光晕一起回到默认；「恢复上一版」可以撤销。",
                                   "Mode, position, sizes, appearance and glow go back to their defaults; Revert to Previous undoes it.")) {
            Button(L10n.text("恢复默认", "Reset to Default"), action: reset)
                .controlSize(.small)
                .disabled(!canReset)
                .accessibilityIdentifier("settings-screen-style-reset")
        }
    }

    /// Gives the screen the default placement and glow, dropping an agent's unsaved style first.
    func reset() { settings.panelLayout.resetLook(screen) }
}

/// The shared layout, once in Settings → Display → Expanded panel: its state, which displays use it, and the two buttons
/// that take effect at once.
struct SharedLayoutRow: View {
    let layout: PanelLayoutStore
    /// The attached displays, of which the row names those that use the shared layout.
    let screens: [ScreensPane.Screen]

    var body: some View {
        SettingRow(label: L10n.text("共用布局", "Shared layout"), subtitle: status + "\n" + users) {
            HStack(spacing: 8) {
                Button(L10n.text("恢复上一版", "Revert to Previous")) { layout.revert() }
                    .disabled(!layout.canRevert)
                    .accessibilityIdentifier("settings-layout-revert")
                Button(L10n.text("恢复默认", "Reset to Default")) { layout.reset() }
                    .disabled(layout.current.isDefault && !layout.hasDraft)
                    .accessibilityIdentifier("settings-layout-reset")
            }
            .controlSize(.small)
        }
    }

    /// Which of its three states the shared layout is in.
    private var status: String {
        if layout.hasDraft { return L10n.text("面板正显示未保存的布局", "The panel shows an unsaved layout") }
        return layout.current.isDefault ? L10n.text("默认布局", "Default layout") : L10n.text("自定义布局", "Custom layout")
    }

    /// The displays whose panel draws the shared layout now.
    private var users: String {
        let names = screens.filter { layout.usesShared($0.key) }.map(\.name)
        guard !names.isEmpty else {
            return L10n.text("每块显示器都在用自己的布局。", "Every display uses a layout of its own.")
        }
        return L10n.text("使用它的显示器：", "Used by ") + names.joined(separator: L10n.text("、", ", "))
    }
}
