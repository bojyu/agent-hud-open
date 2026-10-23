import SwiftUI
import AgentHUDCore
import Observation

@MainActor
@Observable
final class SettingsNavigation {
    var pageID: String
    init(tab: SettingsTab = .display) { pageID = tab.id }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, sources, display, experimental

    /// The pages before a host's own; Experimental comes after them.
    static let leading: [SettingsTab] = [.general, .sources, .display]

    var id: String { rawValue }
    var slug: String { rawValue }

    var label: String {
        switch self {
        case .general: return L10n.text("通用", "General")
        case .sources: return L10n.text("智能体", "Agents")
        case .display: return L10n.text("显示", "Display")
        case .experimental: return L10n.text("实验选项", "Experimental")
        }
    }

    var subtitle: String {
        let simple = ScreenPlacement.onlyMode == .simple
        switch self {
        case .general:
            return simple
                ? L10n.text("设置外观、语言和启动方式。", "Appearance, language and startup preferences.")
                : L10n.text("设置外观、语言、启动方式和客户端回调。", "Appearance, language, startup and client hook preferences.")
        case .sources:
            return simple
                ? L10n.text("管理套餐与显示窗口。", "Manage plans and visible windows.")
                : L10n.text("管理实时状态、套餐与显示窗口。", "Manage live status, plans and visible windows.")
        case .display:
            return simple
                ? L10n.text("自定义额度面板与展开内容，更改自动生效。", "Customize your quota panel and expanded view. Changes apply automatically.")
                : L10n.text("自定义灵动岛光晕与面板内容，更改自动生效。", "Customize your notch and panel. Changes apply automatically.")
        case .experimental: return L10n.text("仍在验证的功能，以后可能会变。", "Features still being tested. They may change.")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .sources: return "puzzlepiece.extension.fill"
        case .display: return "display"
        case .experimental: return "flask.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return Color(hex: 0x8e8e93)
        case .sources: return Color(hex: 0x30b0c7)
        case .display: return Color(hex: 0x7c65e8)
        case .experimental: return Color(hex: 0xff9500)
        }
    }
}

enum SettingsWindowLayout {
    static let size = CGSize(width: 960, height: 720)
    static let minimum = CGSize(width: 880, height: 560)
    static let sidebarWidth: CGFloat = 212
}

struct SettingsView: View {
    let settings: SettingsStore
    let store: UsageStore
    var sourceStatuses: [SourceStatus]?
    var initialProviderID: String?
    let additionalPages: [DesktopSettingsPage]
    /// A host's rows on the Experimental page, a host page with that page's id among them.
    let experimentalSections: [DesktopSettingsSection]
    /// The Experimental page's install row, given where a test or a still stands in for this Mac.
    var clientSetup: MCPClientSetup?
    @State private var navigation: SettingsNavigation
    @Environment(WindowSurface.self) private var surface: WindowSurface?
    @Environment(\.colorScheme) private var scheme

    init(settings: SettingsStore, store: UsageStore, initialTab: SettingsTab = .display,
         navigation: SettingsNavigation? = nil,
         additionalPages: [DesktopSettingsPage] = [],
         experimentalSections: [DesktopSettingsSection] = [],
         clientSetup: MCPClientSetup? = nil,
         sourceStatuses: [SourceStatus]? = nil, initialProviderID: String? = nil) {
        self.settings = settings
        self.store = store
        self.sourceStatuses = sourceStatuses
        self.initialProviderID = initialProviderID
        let builtIn = Set(SettingsTab.allCases.map(\.id))
        self.additionalPages = additionalPages.filter { !builtIn.contains($0.id) }
        self.experimentalSections = experimentalSections + additionalPages.filter { $0.id == SettingsTab.experimental.id }
            .map { page in DesktopSettingsSection(id: page.id) { page.content() } }
        self.clientSetup = clientSetup
        _navigation = State(initialValue: navigation ?? SettingsNavigation(tab: initialTab))
    }

    var body: some View {
        @Bindable var navigation = navigation
        // The window's tokens on the ground its screen's look gives it, with Match screen on (`Theme.under(_:)`).
        let theme = Theme.forScheme(scheme).under(surface?.look)
        HStack(spacing: 0) {
            SettingsSidebar(selection: $navigation.pageID, additionalPages: additionalPages, theme: theme)
                .frame(width: SettingsWindowLayout.sidebarWidth)
                // The border on the sidebar's own ground: a line of its own would leave a slit of desktop under glass.
                .overlay(alignment: .trailing) { Rectangle().fill(theme.sidebarBorder).frame(width: 1) }
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(pageTitle).font(.ui(24, .semibold))
                    if !pageSubtitle.isEmpty {
                        Text(pageSubtitle).font(.ui(12)).foregroundStyle(theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

                if tab == .sources {
                    pane(theme)
                        .padding(.horizontal, 20)
                        .id(navigation.pageID)
                } else {
                    ScrollView {
                        pane(theme)
                            .frame(maxWidth: additionalPage?.preferredContentWidth ?? 640, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                    }
                    .id(navigation.pageID)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            // The page's ground beside the sidebar's, never under it: glass over glass does not see the desktop.
            .background(WindowGround(color: theme.windowBackground))
        }
        .frame(minWidth: SettingsWindowLayout.minimum.width, idealWidth: SettingsWindowLayout.size.width,
               minHeight: SettingsWindowLayout.minimum.height, idealHeight: SettingsWindowLayout.size.height)
        .foregroundStyle(theme.text)
        .font(.ui(13))
        .tint(Color.accentColor)
        .id(settings.settings.language)
    }

    private var tab: SettingsTab? { SettingsTab(rawValue: navigation.pageID) }
    private var additionalPage: DesktopSettingsPage? { additionalPages.first { $0.id == navigation.pageID } }
    private var pageTitle: String { tab?.label ?? additionalPage?.title() ?? "" }
    private var pageSubtitle: String { tab?.subtitle ?? additionalPage?.subtitle() ?? "" }

    @ViewBuilder
    private func pane(_ theme: Theme) -> some View {
        if let tab {
            switch tab {
            case .general: GeneralPane(settings: settings, theme: theme)
            case .sources: SourcesPane(settings: settings, store: store, theme: theme, sources: sourceStatuses,
                                       initialProviderID: initialProviderID)
            case .display: DisplayPane(settings: settings, store: store, theme: theme)
            case .experimental: ExperimentalPane(settings: settings, theme: theme, additions: experimentalSections, setup: clientSetup)
            }
        } else if let additionalPage {
            additionalPage.content()
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: String
    let additionalPages: [DesktopSettingsPage]
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: 44)
            Text(L10n.text("偏好设置", "Preferences"))
                .font(.ui(11, .medium))
                .foregroundStyle(theme.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            ForEach(SettingsTab.leading) { tab in
                pageButton(id: tab.id, title: tab.label, symbol: tab.symbol, color: tab.color)
            }
            ForEach(additionalPages) { page in
                pageButton(id: page.id, title: page.title(), symbol: page.symbol, color: page.color)
            }
            ForEach(SettingsTab.allCases.filter { !SettingsTab.leading.contains($0) }) { tab in
                pageButton(id: tab.id, title: tab.label, symbol: tab.symbol, color: tab.color)
            }
            Spacer()
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppResources.applicationName).font(.ui(12, .semibold)).foregroundStyle(theme.text)
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .font(.ui(11)).foregroundStyle(theme.secondary)
                }
            }
            .padding(12)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        .background(WindowGround(color: theme.sidebarBackground))
    }

    private func pageButton(id: String, title: String, symbol: String, color: Color) -> some View {
        let selected = id == selection
        return Button { selection = id } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(color, in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.ui(13, selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(selected ? .white : theme.sidebarText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-tab-\(id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One titled group for settings content: its title, with what stands beside it if anything, a tag or the group's own
/// action (`accessory`), and its subtitle above; its rows on the group's card (`SettingsCard`) below. Public, with
/// `SettingRow`, `SettingsToggleRow` and `SettingsDivider`, so that the pages a host app adds to Settings are built as
/// the app's own are.
public struct SettingsSection<Accessory: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    /// The window's theme, or nil to take it from the colour scheme the section is drawn in, as a host's page does.
    private let theme: Theme?
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    init(title: String, subtitle: String? = nil, theme: Theme, @ViewBuilder content: @escaping () -> Content)
    where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.theme = theme
        self.accessory = { EmptyView() }
        self.content = content
    }

    public init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content)
    where Accessory == EmptyView {
        self.init(title: title, subtitle: subtitle, accessory: { EmptyView() }, content: content)
    }

    /// A group with `accessory` beside its title.
    public init(title: String, subtitle: String? = nil, @ViewBuilder accessory: @escaping () -> Accessory,
                @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.theme = nil
        self.accessory = accessory
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title).font(.ui(15, .semibold))
                    accessory()
                }
                if let subtitle {
                    Text(subtitle).font(.ui(12)).settingsSubtitle(theme: theme)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 0, content: content)
                .settingsCard()
        }
    }
}

/// The ink of a settings group's subtitle, and of a host's line written as one: the window theme's secondary grey on the
/// window's ground (`Theme.under(_:)`), which on a ground the desktop shows through is a tint of the ink, so that it
/// holds as the ground lightens or darkens, where a fixed copy of the grey would not.
public struct SettingsSubtitle: ViewModifier {
    /// The window's theme, or nil to take it from the colour scheme the view is drawn in.
    var theme: Theme?
    @Environment(WindowSurface.self) private var surface: WindowSurface?
    @Environment(\.colorScheme) private var scheme

    public func body(content: Content) -> some View {
        content.foregroundStyle((theme ?? Theme.forScheme(scheme).under(surface?.look)).secondary)
    }
}

public extension View {
    /// Inks the view as a settings group's subtitle (`SettingsSubtitle`).
    func settingsSubtitle() -> some View {
        modifier(SettingsSubtitle())
    }
}

extension View {
    func settingsSubtitle(theme: Theme?) -> some View {
        modifier(SettingsSubtitle(theme: theme))
    }
}

/// The ground every settings group stands on, Settings → General's: the window theme's card with its hairline, light or
/// dark as the window is, and thinned with the window's ground under a look the desktop shows through (`Theme.under(_:)`).
/// Public so that the pages a host app adds to Settings stand on the same ground as the app's own.
public struct SettingsCard: ViewModifier {
    var cornerRadius: CGFloat = SettingsCard.cornerRadius
    @Environment(\.colorScheme) private var scheme
    @Environment(WindowSurface.self) private var surface: WindowSurface?

    /// The corner of a settings group.
    public static let cornerRadius: CGFloat = 12

    public func body(content: Content) -> some View {
        let theme = Theme.forScheme(scheme).under(surface?.look), shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .background(theme.card, in: shape)
            .overlay(shape.stroke(theme.cardBorder.opacity(0.55), lineWidth: 1))
    }
}

public extension View {
    /// Stands the view on a settings group's ground (`SettingsCard`).
    func settingsCard(cornerRadius: CGFloat = SettingsCard.cornerRadius) -> some View {
        modifier(SettingsCard(cornerRadius: cornerRadius))
    }
}

/// The line between two rows of a settings group.
public struct SettingsDivider: View {
    private let theme: Theme?
    @Environment(\.colorScheme) private var scheme

    init(theme: Theme) { self.theme = theme }

    /// A divider in the theme of the colour scheme it is drawn in, as a host's page draws it.
    public init() { self.theme = nil }

    public var body: some View {
        Rectangle().fill((theme ?? Theme.forScheme(scheme)).divider).frame(height: 1).padding(.horizontal, 16)
    }
}

/// A settings row whose control is a switch.
public struct SettingsToggleRow: View {
    let label: String
    var subtitle: String? = nil
    var tag: String? = nil
    @Binding var isOn: Bool

    public init(label: String, subtitle: String? = nil, tag: String? = nil, isOn: Binding<Bool>) {
        self.label = label
        self.subtitle = subtitle
        self.tag = tag
        self._isOn = isOn
    }

    public var body: some View {
        SettingRow(label: label, subtitle: subtitle, tag: tag) {
            Toggle(label, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}
