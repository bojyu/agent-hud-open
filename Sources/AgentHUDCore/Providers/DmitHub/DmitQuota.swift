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
        let error: String?
        /// Remaining credits and their total, for a channel billed in credits (Notion's allowance, Kie's balance).
        let creditsRemaining: Double?
        let creditsTotal: Double?
        let creditsResetAt: Date?
        /// Codex's earned resets.
        let resetCredits: Int?
        /// Claude's share of use by surface, in percent (`claude_code`, `chat`, `cowork`, `other`).
        let breakdown: [String: Double]
        /// Muse's top-up allowance, in the hub's words.
        let topUpLabel: String?

        /// The hub read this channel on its last pass.
        var isFresh: Bool { status == "fresh" && !stale }
    }

    let updatedAt: Date?
    let channels: [Channel]

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
        default:
            add("five-hour", used: object["five_hour_used"], reset: object["five_hour_resets_at"], duration: 5 * 3600)
            add("seven-day", used: object["seven_day_used"], reset: object["seven_day_resets_at"], duration: 7 * 86400)
        }
        let credits = object["credits"] as? [String: Any]
        let breakdown = (object["breakdown"] as? [String: Any] ?? [:]).compactMapValues(number)
        return Channel(name: name, accountKey: text(object["account_key"]), plan: text(object["plan_type"]), windows: windows,
                       status: text(object["status"]), stale: object["stale"] as? Bool ?? false, fetchedAt: date(object["fetched_at"]),
                       error: text(object["error"]), creditsRemaining: number(credits?["remaining"]),
                       creditsTotal: number(credits?["total"]), creditsResetAt: date(credits?["resets_at"]),
                       resetCredits: number(object["reset_credits"]).map { Int($0) }, breakdown: breakdown,
                       topUpLabel: text(object["topup_label"]))
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
