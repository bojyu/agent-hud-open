import SwiftUI
import AgentHUDCore

struct IslandPane: View {
    let settings: SettingsStore
    let theme: Theme
    /// The look of the HUD whose panel the samples show, which they are drawn with.
    let look: HUDLook

    /// The tokens the samples are drawn with: the look's, as the island's are.
    private var island: Theme { look.theme }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
                SettingsSection(
                    title: L10n.text("展开面板", "Expanded panel"),
                    subtitle: L10n.text("每项展示一个简短示例，开关控制对应内容。", "A small sample for each part. Choose what appears in the panel."),
                    theme: theme
                ) {
                    if ScreenPlacement.onlyMode != .simple {
                        SettingsToggleRow(label: L10n.text("会话列表", "Session list"), isOn: settings.binding(\.showIslandSessions))
                        IslandPartSample(height: 56, look: look, enabled: settings.settings.showIslandSessions) {
                            sessionSample
                        }
                        SettingsDivider(theme: theme)
                    }
                    SettingsToggleRow(label: L10n.text("额度明细", "Quota details"), isOn: settings.binding(\.showIslandQuota))
                    IslandPartSample(height: 64, look: look, enabled: settings.settings.showIslandQuota) {
                        quotaSample
                    }
                    SettingsToggleRow(label: L10n.text("重置倒计时", "Reset countdown"), isOn: settings.binding(\.showResetCountdown))
                    if ScreenPlacement.onlyMode != .simple {
                        SettingsDivider(theme: theme)
                        SettingsToggleRow(label: L10n.text("Token 消耗", "Token usage"), isOn: settings.binding(\.showIslandTokens))
                        IslandPartSample(height: 64, look: look, enabled: settings.settings.showIslandTokens) {
                            tokenSample
                        }
                    }
                    SettingsDivider(theme: theme)
                    // The layout arranges what the switches above leave. A person's click here takes effect at once,
                    // where an agent's change waits in the panel to be saved. A screen with a layout of its own says so
                    // in its part of Screens above.
                    SharedLayoutRow(layout: settings.panelLayout, screens: ScreensPane.attached())
                }
            SettingsSection(title: L10n.text("Logo", "Logos"), theme: theme) {
                SettingsToggleRow(
                    label: L10n.text("Bot 形象", "Bot logos"),
                    subtitle: L10n.text("工作时保持 Bot；空闲时偶尔变成 Bot 活动几秒，再回到 Logo。悬停、等待批准或刚回复时也显示 Bot。",
                                        "Working agents stay bots. Idle logos occasionally become bots for a few seconds. Bots also appear on hover, for approvals and replies."),
                    isOn: settings.binding(\.botLogos)
                )
            }
            SettingsSection(title: L10n.text("悬停交互", "Hover behavior"), theme: theme) {
                SettingsToggleRow(
                    label: L10n.text("按 Option 才展开", "Press Option to open"),
                    subtitle: L10n.text("指针经过不展开，悬停时按一下 Option 打开面板。", "Hovering alone leaves it closed; press Option while hovering to open the panel."),
                    isOn: settings.binding(\.requiresOptionToOpen)
                )
                if ScreenPlacement.onlyMode != .simple {
                    SettingsDivider(theme: theme)
                    SettingsToggleRow(
                        label: L10n.text("鼠标触顶立即展开", "Open immediately at the top edge"),
                        subtitle: L10n.text("鼠标移到 HUD 正上方的屏幕顶边时，跳过展开延迟。", "Skip the hover delay when the pointer reaches the screen's top edge directly above the HUD."),
                        isOn: settings.binding(\.openImmediatelyAtTop)
                    )
                }
                SettingsDivider(theme: theme)
                SliderRow(label: L10n.text("展开延迟", "Hover delay"), value: settings.doubleBinding(\.hoverDelayMs), range: 0...1500, step: 50, format: { "\(Int($0)) ms" }, theme: theme)
                SettingsDivider(theme: theme)
                SliderRow(label: L10n.text("收起延迟", "Collapse delay"), value: settings.doubleBinding(\.collapseDelayMs), range: 0...1500, step: 50, format: { "\(Int($0)) ms" }, theme: theme)
            }
        }
    }

    private var quotaSample: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                AgentLogo(vendor: "Claude", size: 12)
                Text("Claude").fontWeight(.semibold)
                Spacer()
                IslandQuotaMetricPicker(selection: .constant(.quota), theme: island)
            }
            .font(.ui(11)).foregroundStyle(island.secondary)
            HStack(spacing: 10) {
                Circle().fill(island.status(.ok)).frame(width: 7, height: 7)
                Text(IslandSampleData.session.name).font(.ui(12, .semibold)).fixedSize()
                ProgressTrack(fraction: 0.28, fill: island.status(.ok), track: island.track)
                    .frame(height: 4)
                Text("28%").font(.tabular(12, .semibold)).foregroundStyle(island.status(.ok))
                if settings.settings.showResetCountdown {
                    Text(L10n.text("2 小时 14 分", "2h 14m"))
                        .font(.tabular(11)).foregroundStyle(island.secondary)
                        .frame(width: 78, alignment: .trailing)
                }
            }
        }
    }

    private var tokenSample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L10n.text("Token 消耗", "Tokens")).fontWeight(.semibold)
                Spacer()
                Text(L10n.text("1 小时 · 46M tok", "1hr · 46M tok"))
                    .font(.tabular(11)).foregroundStyle(island.secondary)
            }
            TokenBarsChart(columns: IslandSampleData.columns, interval: IslandSampleData.interval,
                           colors: IslandSampleData.colors, consumers: IslandSampleData.consumers, theme: island,
                           context: .island, compact: true)
                .frame(height: 42)
        }
        .font(.ui(11))
    }

    private var sessionSample: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L10n.text("会话", "Sessions")).fontWeight(.semibold)
                Spacer()
                Text(L10n.text("1 个运行中", "1 running"))
            }
            HStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    AgentLogo(vendor: "Claude", size: 14)
                    Circle().fill(island.status(.ok)).frame(width: 6, height: 6)
                        .overlay(Circle().stroke(island.islandFill, lineWidth: 1.5)).offset(x: 2, y: 2)
                }
                .frame(width: 14, height: 14)
                Text(L10n.text("修复登录问题", "Fix sign-in issue"))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "questionmark.bubble.fill").font(.system(size: 9, weight: .semibold))
                    Text("1").font(.tabular(9, .semibold))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(island.status(.warning).opacity(0.16)))
                .foregroundStyle(island.status(.warning))
                Text("60k tok")
            }
            .foregroundStyle(island.secondary)
        }
        .font(.ui(11))
    }
}

/// A fixed-size sample stays in place when its corresponding panel content is switched off. It is drawn on the island's
/// card, in the look of the HUD it stands for, which it takes as the island does (`islandLook(_:)`): the standard look
/// leaves its colour scheme to the window, as the island leaves it to the app. A card of glass is its stand-in, its tint
/// over the pane: the window has no desktop of the HUD's to show through it.
private struct IslandPartSample<Content: View>: View {
    let height: CGFloat
    let look: HUDLook
    let enabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .foregroundStyle(look.theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .padding(.horizontal, 14)
            .opacity(enabled ? 1 : 0.25)
            .background(HUDSurface(RoundedRectangle(cornerRadius: 9), look: look, fill: look.theme.islandFill, contact: nil))
            .islandLook(look)
            .environment(\.drawsGlassStandIn, true)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Deliberately small, stable fixtures; settings samples never grow with the user's account history.
private enum IslandSampleData {
    /// Claude's session window, as its provider builds it.
    static let session = AgentDescriptor(id: ClaudeUsage.sessionRowId, vendor: "Claude", model: L10n.windowSession,
                                         source: L10n.sourceClaudeCode, enabled: true)
    static let consumers = [
        AgentDescriptor(id: "sample-claude", vendor: "Claude", model: "Opus", source: "", enabled: true),
        AgentDescriptor(id: "sample-codex", vendor: "Codex", model: "GPT", source: "", enabled: true),
    ]
    static let colors = [AgentPalette.swiftUIColor(index: 0), AgentPalette.swiftUIColor(index: 1)]
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let interval = StatsRange.hours24.interval(endingAt: now)
    static let columns: [TokenColumn] = {
        let amounts = [4, 8, 5, 11, 16, 9, 6, 13, 20, 14, 10, 7]
        let buckets = (0..<24).flatMap { hour in
            consumers.enumerated().map { index, consumer in
                let count = amounts[(hour + index * 4) % amounts.count] * 1000
                return UsageBucket(
                    start: interval.start.addingTimeInterval(Double(hour) * 3600 + 1800),
                    agentId: consumer.id, tokensIn: count * 4 / 5, tokensOut: count / 5
                )
            }
        }
        return ChartData.tokenBars(usage: buckets, agentIds: consumers.map(\.id), range: .hours24, now: now)
    }()
}
