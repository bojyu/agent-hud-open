import AgentHUDSupport
import Foundation
import Security

/// Every quota reading from the Dmit quota hub (`/opt/ai-quota`) and nothing from this Mac: no local logs, no client
/// logins, no hooks. The hub reads each channel every 120 s; this provider reads the hub's last answer as often, keeps
/// the last good answer through a failed request, and never shows a channel the hub could not read as 0 %.
public actor DmitHubProvider: UsageProvider {
    /// The hub's own collection interval, which reading it any more often would only repeat.
    public static let readInterval: TimeInterval = 120
    static let source = "Dmit 配额中心"

    /// Each hub channel's vendor, as rows and the vendor catalog name it.
    static let vendors = ["claude": "Claude", "codex": "Codex", "antigravity": "Antigravity", "muse": "Muse", "notion": "Notion",
                          "kie": "Kie"]

    private let base: URL
    private let authorization: @Sendable () -> String?
    private let http: ProviderHTTP
    private let history: QuotaHistoryStore
    private let clock: @Sendable () -> Date
    private var last: (at: Date, quota: DmitQuota)?
    /// Why the last request failed; cleared by the next one that succeeds.
    private var failure: String?

    /// - base: the hub's address, under which `api/quota` and `api/refresh` are served.
    /// - authorization: the `Authorization` header value, read for every request; nil sends none.
    init(base: URL, authorization: @escaping @Sendable () -> String?, http: ProviderHTTP = ProviderHTTP(),
         history: QuotaHistoryStore = QuotaHistoryStore(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base
        self.authorization = authorization
        self.http = http
        self.history = history
        self.clock = clock
    }

    /// The hub behind Caddy at `jev.bojyu.world:8443/quota/`, or `AGENT_HUD_DMIT_URL`, signed in with the internet
    /// password the keychain holds for that host. Readings go to `ledger`, so burn rates survive restarts.
    public static func standard(ledger: UsageLedger) -> DmitHubProvider {
        let base = ProcessInfo.processInfo.environment["AGENT_HUD_DMIT_URL"].flatMap(URL.init(string:))
            ?? URL(string: "https://jev.bojyu.world:8443/quota/")!
        let host = base.host ?? ""
        return DmitHubProvider(base: base, authorization: { basicAuthorization(server: host) },
                               history: QuotaHistoryStore(ledger: ledger, scope: "dmit"))
    }

    /// The `Basic` header for the keychain's internet password for `server`; nil when the keychain has none.
    static func basicAuthorization(server: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword, kSecAttrServer as String: server,
                                    kSecReturnData as String: true, kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let item = result as? [String: Any],
              let user = item[kSecAttrAccount as String] as? String, let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
    }

    public nonisolated var seesLocalWork: Bool { false }

    public func refreshAccountUsage(historyHours: Int) async {
        let now = clock()
        do {
            let quota = try DmitQuota.parse(await send(path: "api/quota"))
            try Task.checkCancellation()
            last = (now, quota)
            failure = nil
            await history.append(Self.rows(quota).compactMap { row in
                // Only a window the hub read on its last pass is a new reading; a kept value would repeat an old one.
                guard row.channel.isFresh else { return nil }
                return QuotaSample(agentId: row.id, timestamp: row.channel.fetchedAt ?? now, remainingPct: row.remaining)
            }, now: now)
        } catch {
            if Task.isCancelled { return }
            failure = L10n.text("无法读取 Dmit 配额中心：", "Dmit quota hub unavailable: ") + error.localizedDescription
        }
    }

    /// Asks the hub to read every channel now, then reads its answer.
    public func requestCollection() async throws {
        _ = try await send(path: "api/refresh", method: "POST")
        await refreshAccountUsage(historyHours: 24)
    }

    public func accountChecks(since: [String: Date], spread: [String: TimeInterval], now: Date) async -> [String: Date] {
        ["": (since[""] ?? .distantPast).addingTimeInterval(Self.readInterval)]
    }

    public func fetchUsage(agents: [AgentDescriptor], historyHours: Int) async throws -> UsageReport {
        let now = clock()
        guard let last else {
            return UsageReport(generatedAt: now, snapshots: [], sessions: [],
                               notice: failure ?? L10n.text("等待 Dmit 配额中心", "Waiting for the Dmit quota hub"))
        }
        let rows = Self.rows(last.quota)
        var snapshots: [UsageSnapshot] = [], insights: [String: UsageInsights] = [:]
        for row in rows {
            // Claude's session row carries its weekly window too, as Claude Code's own provider gives it.
            let weekly = row.window.key == ClaudeUsage.sessionRowId
                ? rows.first { $0.channel.name == row.channel.name && $0.window.key == ClaudeUsage.weeklyRowId } : nil
            let snapshot = UsageSnapshot(agentId: row.id, remainingPct: row.remaining, weeklyRemainingPct: weekly?.remaining,
                                         resetAt: row.window.resetAt, windowDuration: row.window.duration,
                                         weeklyResetAt: weekly?.window.resetAt, updatedAt: row.channel.fetchedAt ?? last.at)
            snapshots.append(snapshot)
            let samples = await history.samples(agentId: row.id, since: QuotaMath.historyStart(for: snapshot, now: now))
            insights[row.id] = QuotaMath.insights(snapshot: snapshot, samples: samples, now: now)
        }
        var issues: [String: ReadingIssue] = [:], accounts: [String: [AccountObservation]] = [:]
        var subscriptions: [String: String] = [:], billing: [APIBilling] = []
        var resetCredits: CodexResetCredits?
        for channel in last.quota.channels {
            guard let vendor = Self.vendors[channel.name] else { continue }
            let issue = failure.map(ReadingIssue.readFailed) ?? Self.issue(channel)
            if let issue { issues[vendor] = issue }
            if let plan = channel.plan { subscriptions[vendor] = plan }
            if channel.name == "kie" {
                billing.append(APIBilling(vendor: vendor, balances: channel.creditsRemaining.map {
                    [AccountBalance(currency: "credits", total: Decimal($0), granted: 0, toppedUp: 0)]
                } ?? [], isAvailable: channel.creditsRemaining.map { $0 > 0 }, updatedAt: channel.fetchedAt ?? last.at,
                    notice: issue?.reason, readingIssue: issue))
                continue
            }
            let account = Self.account(channel)
            let windowIDs = Set(rows.filter { $0.channel.name == channel.name }.map(\.id))
            if channel.name == "codex", let count = channel.resetCredits {
                resetCredits = CodexResetCredits(availableCount: count, credits: nil)
            }
            accounts[vendor] = [AccountObservation(account: account, client: vendor, plan: channel.plan,
                observedAt: channel.fetchedAt ?? last.at, quotaNotice: issue?.reason, readingIssue: issue,
                resetCredits: channel.name == "codex" ? resetCredits : nil,
                // Only a sound reading lists every window, so a channel that failed keeps the rows it had.
                quotaWindowIDs: issue == nil ? windowIDs : nil, sourceInfo: Self.sourceInfo(channel))]
        }
        let descriptors = rows.map { row in
            AgentDescriptor(id: row.id, vendor: row.vendor, model: row.label, shortModel: row.shortLabel, source: Self.source,
                            enabled: true, account: Self.account(row.channel))
        }
        let notices = issues.mapValues(\.reason)
        return UsageReport(generatedAt: now, snapshots: snapshots, sessions: [], discoveredAgents: descriptors, consumers: [],
                           insightsByAgent: insights, subscriptions: subscriptions, sourceNotices: notices, quotaNotices: notices,
                           readingIssues: issues, billing: billing, codexResetCredits: resetCredits,
                           codexResetCreditsObservedAt: resetCredits == nil ? nil : last.quota.channel("codex")?.fetchedAt,
                           accounts: accounts)
    }

    // MARK: - Mapping

    /// One quota row: a channel's window, or Notion's credit allowance as a window of its own.
    struct Row {
        let channel: DmitQuota.Channel
        let window: DmitQuota.Window
        var vendor: String { DmitHubProvider.vendors[channel.name] ?? channel.name }
        var id: String { DmitHubProvider.account(channel).windowID(window.key) }
        var remaining: Double { min(100, max(0, 100 - window.usedPct)) }

        var label: String {
            switch window.key {
            case ClaudeUsage.sessionRowId: return L10n.windowSession
            case ClaudeUsage.weeklyRowId: return L10n.windowWeekly
            case "credits": return L10n.text("积分", "Credits")
            default: return CodexRateLimits.limitName(WindowNames.Period(seconds: window.duration), secondary: false)
            }
        }

        /// Claude's short names come from its persisted keys; every other window gives its period.
        var shortLabel: String? {
            switch window.key {
            case ClaudeUsage.sessionRowId, ClaudeUsage.weeklyRowId: return nil
            case "credits": return L10n.text("积分", "Credits")
            default: return WindowNames.Period(seconds: window.duration)?.shortName ?? label
            }
        }
    }

    static func rows(_ quota: DmitQuota) -> [Row] {
        quota.channels.filter { vendors[$0.name] != nil }.flatMap { channel -> [Row] in
            var windows = channel.windows
            if channel.name == "notion", let remaining = channel.creditsRemaining, let total = channel.creditsTotal, total > 0 {
                windows.append(.init(key: "credits", usedPct: (total - remaining) / total * 100, resetAt: channel.creditsResetAt,
                                     duration: nil))
            }
            return windows.map { Row(channel: channel, window: $0) }
        }
    }

    /// The hub's account key, hashed again as every account id is; a channel without one is the hub's single account.
    static func account(_ channel: DmitQuota.Channel) -> ProviderAccount {
        let vendor = vendors[channel.name] ?? channel.name
        return ProviderAccount.identified(provider: vendor, user: channel.accountKey ?? "dmit:" + channel.name, workspace: nil)!
    }

    /// A channel the hub could not read on its last pass keeps its last values, held back from alerts and levels.
    static func issue(_ channel: DmitQuota.Channel) -> ReadingIssue? {
        guard !channel.isFresh else { return nil }
        return .readFailed(channel.error ?? L10n.text("Dmit 上的数据已过期", "Data on Dmit is out of date"))
    }

    /// What has no field of its own yet: Claude's use by surface and Muse's top-up allowance.
    static func sourceInfo(_ channel: DmitQuota.Channel) -> String? {
        var parts: [String] = []
        let surfaces = [("claude_code", "Claude Code"), ("chat", "Chat"), ("cowork", "Cowork"), ("other", L10n.text("其他", "Other"))]
        let shares = surfaces.compactMap { key, name in channel.breakdown[key].map { "\(name) \(Int($0.rounded()))%" } }
        if !shares.isEmpty { parts.append(L10n.text("用量来源：", "Usage by surface: ") + shares.joined(separator: " · ")) }
        if let topUp = channel.topUpLabel { parts.append(L10n.text("加量包：", "Top-up: ") + topUp) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func send(path: String, method: String = "GET") async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization = authorization() { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return try await http.send(request)
    }
}
