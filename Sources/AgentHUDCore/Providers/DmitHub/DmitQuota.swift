import Foundation

/// One answer of the Dmit quota hub's `GET /api/quota`: every channel the hub collects, as the hub last read it.
/// Percentages are used, not remaining; times are ISO strings or Unix seconds, both read here as dates.
struct DmitQuota: Hashable, Sendable {
    /// One quota window of a channel, as the hub reported it.
    struct Window: Hashable, Sendable {
        /// The window's key within its channel, which becomes its row's window key (`claude-session`, `codex`, `rolling`).
        let key: String
        let usedPct: Double
        let resetAt: Date?
        let duration: TimeInterval?
        var label: String? = nil
        var group: String? = nil
        var allModels: Bool = true
    }

    /// One channel: a vendor's windows, plan and reading health.
    struct Channel: Hashable, Sendable {
        let name: String
        /// The hub's hashed account key; nil for a channel that names no account (Claude).
        let accountKey: String?
        let plan: String?
        let windows: [Window]
        /// `fresh` while the hub's last read succeeded; anything else keeps the last good values.
        let status: String?
        let stale: Bool
        let fetchedAt: Date?
        let nextAttemptAt: Date?
        let error: String?
        /// Remaining credits and their total, for a channel billed in credits (Notion's allowance, Kie's balance).
        let creditsRemaining: Double?
        let creditsTotal: Double?
        let creditsResetAt: Date?
        /// The money a balance is counted in (`CNY` for DeepSeek); nil for one counted in credits (Kie).
        let creditsCurrency: String?
        /// A balance's granted and topped-up parts, where the hub reads them apart.
        let creditsGranted: Double?
        let creditsToppedUp: Double?
        /// Codex's earned resets.
        let resetCredits: Int?
        /// Claude's share of use by surface, in percent (`claude_code`, `chat`, `cowork`, `other`).
        let breakdown: [String: Double]
        /// Muse's top-up allowance, in the hub's words.
        let topUpLabel: String?
        /// What the account's API calls have cost this calendar month, and the money it is counted in (Anthropic).
        let monthSpend: Double?
        let spendCurrency: String?
        /// Absolute amounts stay available beside the percentage windows.
        let creditsUsed: Double?
        let cloudAmounts: [String: Double]

        /// The hub read this channel on its last pass.
        var isFresh: Bool { status == "fresh" && !stale }
    }

    let updatedAt: Date?
    let channels: [Channel]

    /// Claude Code's cloud session credits, a window of Claude's own.
    static let cloudRowId = "claude-cloud"

    func channel(_ name: String) -> Channel? { channels.first { $0.name == name } }

    static func parse(_ data: Data) throws -> DmitQuota {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any] else { throw ProviderFailure.format }
        let channels = providers.keys.sorted().compactMap { name -> Channel? in
            guard let object = providers[name] as? [String: Any] else { return nil }
            return channel(name, object)
        }
        return DmitQuota(updatedAt: date(root["updated_at"]), channels: channels)
    }

    private static func channel(_ name: String, _ object: [String: Any]) -> Channel {
        var windows: [Window] = []
        func add(_ key: String, used: Any?, reset: Any?, duration: TimeInterval?) {
            guard let used = number(used) else { return }
            windows.append(Window(key: key, usedPct: used, resetAt: date(reset), duration: duration))
        }
        switch name {
        case "claude":
            add(ClaudeUsage.sessionRowId, used: object["five_hour_used"], reset: object["five_hour_resets_at"], duration: 5 * 3600)
            add(ClaudeUsage.weeklyRowId, used: object["seven_day_used"], reset: object["seven_day_resets_at"], duration: 7 * 86400)
            // The cloud session credits the plan was granted, used up to the day they expire.
            let cloud = object["cloud"] as? [String: Any]
            add(cloudRowId, used: cloud?["used_pct"], reset: cloud?["resets_at"], duration: nil)
        case "codex":
            for case let window as [String: Any] in object["quota_windows"] as? [Any] ?? [] {
                let kind = window["kind"] as? String ?? "primary"
                // The primary window keeps the Codex provider's own window key, as its row there does.
                add(kind == "primary" ? "codex" : "codex:\(kind)", used: window["used_percent"], reset: window["resets_at"],
                    duration: number(window["window_seconds"]))
            }
        case "notion":
            add("rolling", used: object["rolling_used"], reset: object["rolling_resets_at"], duration: number(object["rolling_window_seconds"]))
            add("monthly", used: object["monthly_used"], reset: object["monthly_resets_at"], duration: 30 * 86400)
        case "antigravity":
            let rawWindows = (object["quota_windows"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
            if !rawWindows.isEmpty {
                let groups = Set(rawWindows.compactMap { text($0["group"]) })
                for window in rawWindows {
                    guard let id = text(window["id"]), let used = number(window["used_percent"]) else { continue }
                    let group = text(window["group"])
                    let bucketName = text(window["name"]) ?? id
                    let fullLabel = [group, bucketName].compactMap { $0 }.joined(separator: " · ")
                    windows.append(Window(
                        key: id.hasPrefix("antigravity:") ? id : "antigravity:\(id)",
                        usedPct: used,
                        resetAt: date(window["resets_at"]),
                        duration: number(window["window_seconds"]),
                        label: fullLabel,
                        group: group,
                        allModels: groups.count <= 1
                    ))
                }
            } else {
                add("five-hour", used: object["five_hour_used"], reset: object["five_hour_resets_at"], duration: 5 * 3600)
                add("seven-day", used: object["seven_day_used"], reset: object["seven_day_resets_at"], duration: 7 * 86400)
            }
        default:
            add("five-hour", used: object["five_hour_used"], reset: object["five_hour_resets_at"], duration: 5 * 3600)
            add("seven-day", used: object["seven_day_used"], reset: object["seven_day_resets_at"], duration: 7 * 86400)
        }
        let credits = object["credits"] as? [String: Any]
        let spend = object["spend"] as? [String: Any]
        let breakdown = (object["breakdown"] as? [String: Any] ?? [:]).compactMapValues(number)
        return Channel(name: name, accountKey: text(object["account_key"]), plan: text(object["plan_type"]), windows: windows,
                       status: text(object["status"]), stale: object["stale"] as? Bool ?? false, fetchedAt: date(object["fetched_at"]),
                       nextAttemptAt: date(object["next_attempt_at"]), error: text(object["error"]), creditsRemaining: number(credits?["remaining"]),
                       creditsTotal: number(credits?["total"]), creditsResetAt: date(credits?["resets_at"]),
                       creditsCurrency: text(credits?["currency"]), creditsGranted: number(credits?["granted"]),
                       creditsToppedUp: number(credits?["topped_up"]),
                       resetCredits: number(object["reset_credits"]).map { Int($0) }, breakdown: breakdown,
                       topUpLabel: text(object["topup_label"]), monthSpend: number(spend?["month_used"]),
                       spendCurrency: text(spend?["currency"]), creditsUsed: number(credits?["used"]),
                       cloudAmounts: (object["cloud"] as? [String: Any] ?? [:]).compactMapValues(number))
    }

    /// A number, never a Boolean that JSONSerialization also hands back as an NSNumber.
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let double = value.doubleValue
        return double.isFinite ? double : nil
    }

    /// An ISO 8601 string or Unix seconds.
    static func date(_ value: Any?) -> Date? {
        if let string = value as? String { return DateParsing.iso8601(string) }
        return number(value).map(Date.init(timeIntervalSince1970:))
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return string
    }
}
