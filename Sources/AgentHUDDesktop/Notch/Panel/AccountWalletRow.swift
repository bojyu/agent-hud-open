import SwiftUI
import AgentHUDCore

/// Wallet money belongs to the account beside its quota windows. Its amounts never imply a subscription percentage. In
/// half a line, which has no bar rows to line up with, the name is as wide as it is, and the amounts go under it where
/// they do not fit beside it.
struct AccountWalletRow: View {
    let wallet: AccountWallet
    @Environment(\.hudTheme) private var theme
    @Environment(\.panelHalf) private var half

    var body: some View {
        let labels = AccountWalletLabels(wallet: wallet)
        Group {
            if half {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: IslandRowLayout.halfSpacing) {
                        name(labels)
                        Spacer(minLength: 8)
                        amounts(labels)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: IslandRowLayout.halfSpacing) { name(labels) }
                        amounts(labels).padding(.leading, IslandRowLayout.markerWidth + IslandRowLayout.halfSpacing)
                    }
                }
            } else {
                HStack(spacing: IslandRowLayout.spacing) {
                    name(labels)
                    Spacer(minLength: 8)
                    amounts(labels)
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, IslandRowLayout.inset)
        .padding(.vertical, 2)
        .help(wallet.observedAt.map { at in
            let date = at.formatted(Date.FormatStyle().month(.abbreviated).day()
                .hour().minute().second().locale(L10n.dateLocale))
            return L10n.text("读取时间：\(date)", "Read at: \(date)")
        } ?? "")
        .accessibilityElement(children: .combine)
    }

    /// The wallet's mark and its name, in the name column of a bar row's width across the whole line.
    @ViewBuilder
    private func name(_ labels: AccountWalletLabels) -> some View {
        Image(systemName: symbol)
            .font(.ui(10))
            .foregroundStyle(theme.tertiary)
            .frame(width: IslandRowLayout.markerWidth)
        Text(labels.name)
            .font(.ui(12, .medium))
            .foregroundStyle(theme.secondary)
            .frame(width: half ? nil : IslandRowLayout.nameWidth, alignment: .leading)
    }

    private var symbol: String {
        switch wallet.kind {
        case .prepaid: "creditcard"
        case .onDemand: "dollarsign.circle"
        case .monthlySpend: "chart.bar"
        }
    }

    private func amounts(_ labels: AccountWalletLabels) -> some View {
        Text(labels.amounts)
            .font(.tabular(12, .semibold))
            .foregroundStyle(theme.text)
    }
}

/// Keep a reported zero distinct from a field the source omitted.
struct AccountWalletLabels {
    let wallet: AccountWallet

    var name: String {
        switch wallet.kind {
        case .prepaid: L10n.text("预付余额", "Prepaid balance")
        case .onDemand: L10n.text("按需付费", "On-demand")
        case .monthlySpend: L10n.text("API 本月支出", "API spend this month")
        }
    }

    var amounts: String {
        switch wallet.kind {
        case .prepaid: amount(wallet.balance)
        case .monthlySpend: amount(wallet.used)
        case .onDemand:
            L10n.text("已用 \(amount(wallet.used)) · 上限 \(amount(wallet.limit))",
                      "Used \(amount(wallet.used)) · Limit \(amount(wallet.limit))")
        }
    }

    private func amount(_ value: Decimal?) -> String {
        value.map { MoneyFormat.amount($0, currency: wallet.currency) } ?? "N/A"
    }
}
