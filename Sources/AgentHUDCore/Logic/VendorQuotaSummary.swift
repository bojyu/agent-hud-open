import Foundation

/// One vendor's quota at a glance: its rows, and the window its ring shows. Rows whose vendors share a mark share a
/// summary (`VendorMark.key`): two Claude windows are one Claude, Codex and ChatGPT one OpenAI.
public struct VendorQuotaSummary: Identifiable, Hashable, Sendable {
    /// The first vendor seen under this mark, which names it.
    public let vendor: String
    /// The mark the vendor is drawn with.
    public let markKey: String
    /// Every row under this mark, in row order.
    public let rows: [AgentRow]
    /// Share used of the window the ring shows, 0…100; nil until a window has a reading that shows a level.
    public let usedPct: Double?
    /// That window's level.
    public let level: StatusLevel?
    /// The row the ring shows; nil before a reading that shows a level.
    public let shownRowID: String?

    public var id: String { markKey }

    /// The one window a vendor's ring shows whatever the others read, by vendor and window key: Notion's monthly
    /// allowance rather than its six-hour window or its credits, and Claude's weekly window rather than its session or
    /// its cloud credits.
    public static let pinnedWindows = ["Notion": "monthly", "Claude": ClaudeUsage.weeklyRowId]

    /// One summary per mark, in row order. Each shows its pinned window when it has one, else the most consumed of its
    /// windows; only a reading that shows a level counts, the rule the menu bar's figure follows.
    public static func summaries(rows: [AgentRow]) -> [VendorQuotaSummary] {
        var order: [String] = []
        var vendors: [String: String] = [:]
        var grouped: [String: [AgentRow]] = [:]
        var tightest: [String: (used: Double, level: StatusLevel, id: String)] = [:]
        for row in rows {
            let key = VendorMark.key(row.agent.vendor)
            if vendors[key] == nil {
                order.append(key)
                vendors[key] = row.agent.vendor
            }
            grouped[key, default: []].append(row)
            if let pinned = pinnedWindows[row.agent.vendor], row.agent.windowKey != pinned,
               rows.contains(where: { $0.agent.vendor == row.agent.vendor && $0.agent.windowKey == pinned }) { continue }
            guard row.assessment.showsLevel, let used = row.usedPct, let level = row.level,
                  used > (tightest[key]?.used ?? -1) else { continue }
            tightest[key] = (used, level, row.id)
        }
        return order.map { key in
            VendorQuotaSummary(vendor: vendors[key] ?? key, markKey: key, rows: grouped[key] ?? [],
                               usedPct: tightest[key]?.used, level: tightest[key]?.level, shownRowID: tightest[key]?.id)
        }
    }
}
