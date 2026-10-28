import Foundation
import XCTest
@testable import AgentHUDCore

final class DmitHubProviderTests: XCTestCase {
    /// `GET /api/quota` as the hub answered it on 2026-10-17, with its account keys replaced: Codex's sign-in had
    /// expired, so its channel is stale and keeps its last values.
    static let sample = #"""
    {"updated_at": "2026-10-17T06:17:13.471344+00:00", "timestamp": 1792217833,
     "providers": {
      "claude": {"available": true, "five_hour_used": 14.0, "five_hour_resets_at": "2026-10-17T09:19:59.559920+00:00",
                 "seven_day_used": 24.0, "seven_day_resets_at": "2026-10-22T14:59:59.559940+00:00",
                 "breakdown": {"claude_code": 83, "chat": 6, "cowork": 11, "other": 0},
                 "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.649685+00:00"},
      "codex": {"available": true, "account_key": "fixture-codex", "plan_type": "prolite",
                "quota_windows": [{"kind": "primary", "used_percent": 100.0, "window_seconds": 604800, "resets_at": 1792472361}],
                "reset_credits": 0, "reset_credits_applicable": 0, "status": "stale", "stale": true,
                "fetched_at": "2026-10-15T06:10:49.063018+00:00", "error": "登录凭据需要更新"},
      "antigravity": {"available": true, "five_hour_used": 10.0, "five_hour_resets_at": "2026-10-17T09:33:36Z",
                      "seven_day_used": 4.0, "seven_day_resets_at": "2026-10-24T04:33:36Z",
                      "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:13.471344+00:00"},
      "muse": {"available": true, "account_key": "fixture-muse", "seven_day_used": 3, "seven_day_resets_at": 1792720686,
               "plan_type": "Muse Free", "topup_label": "0% used (31B tokens left)",
               "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.607246+00:00"},
      "notion": {"available": true, "account_key": "fixture-notion", "rolling_used": 3.2, "rolling_window_seconds": 21600,
                 "rolling_resets_at": 1792237160.5670056, "monthly_used": 27.8, "monthly_resets_at": 1794567600.0,
                 "credits": {"available": true, "used": 135.538983, "total": 300, "remaining": 164.461017, "resets_at": 1794567600.0},
                 "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:11.167609+00:00"},
      "kie": {"available": true, "account_key": "fixture-kie",
              "credits": {"available": true, "used": null, "total": null, "remaining": 854.0, "resets_at": null},
              "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.416379+00:00"},
      "deepseek": {"available": true, "account_key": "fixture-deepseek",
                   "credits": {"available": true, "remaining": 110.5, "granted": 10.0, "topped_up": 100.5, "currency": "CNY",
                               "remaining_kind": "balance", "resets_at": null},
                   "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.416379+00:00"},
      "openrouter": {"available": true, "account_key": "fixture-openrouter",
                     "credits": {"available": true, "used": 14.5, "total": 20.0, "remaining": 5.5, "granted": 0.0,
                                 "topped_up": 5.5, "currency": "USD", "remaining_kind": "balance", "resets_at": null},
                     "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.416379+00:00"}
     },
     "totals": {"today_cost": 0, "today_tokens": 0, "date": "2026-10-17", "stale": false}}
    """#

    static let now = Date(timeIntervalSince1970: 1_792_217_900)

    /// Answers each request from `answer` and records it.
    actor Hub {
        var requests: [URLRequest] = []
        var answer: @Sendable (URLRequest) throws -> Data

        init(_ answer: @escaping @Sendable (URLRequest) throws -> Data) { self.answer = answer }

        func respond(_ request: URLRequest) throws -> Data {
            requests.append(request)
            return try answer(request)
        }

        func set(_ answer: @escaping @Sendable (URLRequest) throws -> Data) { self.answer = answer }
    }

    /// A clock a test moves on.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var time = DmitHubProviderTests.now
        var now: Date { lock.withLock { time } }
        func advance(_ seconds: TimeInterval) { lock.withLock { time += seconds } }
    }

    /// A retry an hour away unless asked for, so a failed request in a test is tried again only when the test means it.
    private func provider(_ hub: Hub, authorization: String? = "Basic Zml4dHVyZQ==", clock: Clock = Clock(),
                          retryDelays: [TimeInterval] = [3600]) -> DmitHubProvider {
        DmitHubProvider(base: URL(string: "https://hub.example/quota/")!, authorization: { authorization },
                        http: ProviderHTTP(send: { try await hub.respond($0) }), clock: { clock.now }, retryDelays: retryDelays)
    }

    private static func row(_ report: UsageReport, _ vendor: String, _ window: String) -> UsageSnapshot? {
        report.snapshots.first { snapshot in
            report.discoveredAgents.contains { $0.id == snapshot.agentId && $0.vendor == vendor && $0.windowKey == window }
        }
    }

    func testRateLimitedChannelShowsLastReadingAndNextAttempt() async throws {
        let hub = Hub { _ in Data(#"""
        {"providers":{"claude":{"available":true,"five_hour_used":14,"status":"stale","stale":true,
          "fetched_at":"2026-10-17T06:00:00Z","next_attempt_at":"2026-10-17T07:00:00Z",
          "error":"平台暂时限制查询频率"}}}
        """#.utf8) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(Self.row(report, "Claude", ClaudeUsage.sessionRowId)?.remainingPct, 86)
        let channel = try XCTUnwrap(try DmitQuota.parse(Data(#"""
        {"providers":{"claude":{"next_attempt_at":"2026-10-17T07:00:00Z"}}}
        """#.utf8)).channel("claude"))
        XCTAssertEqual(channel.nextAttemptAt, DateParsing.iso8601("2026-10-17T07:00:00Z"))
        let reason = try XCTUnwrap(report.readingIssues?["Claude"]?.reason)
        XCTAssertTrue(reason.contains("平台暂时限制查询频率"))
        XCTAssertGreaterThan(reason.components(separatedBy: " · ").count, 2)
        XCTAssertEqual(DmitHubProvider.readInterval, 600)
    }

    func testMapsEveryChannelToItsWindows() async throws {
        let hub = Hub { _ in Data(Self.sample.utf8) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)

        let session = try XCTUnwrap(Self.row(report, "Claude", ClaudeUsage.sessionRowId))
        XCTAssertEqual(session.remainingPct, 86)
        XCTAssertEqual(session.weeklyRemainingPct, 76)
        XCTAssertEqual(session.windowDuration, 5 * 3600)
        XCTAssertEqual(try XCTUnwrap(session.resetAt?.timeIntervalSince1970),
                       try XCTUnwrap(DateParsing.iso8601("2026-10-17T09:19:59.559Z")?.timeIntervalSince1970), accuracy: 0.001)
        XCTAssertEqual(Self.row(report, "Claude", ClaudeUsage.weeklyRowId)?.remainingPct, 76)

        let codex = try XCTUnwrap(Self.row(report, "Codex", "codex"))
        XCTAssertEqual(codex.remainingPct, 0)
        XCTAssertEqual(codex.windowDuration, 604_800)
        XCTAssertEqual(codex.resetAt, Date(timeIntervalSince1970: 1_792_472_361))

        XCTAssertEqual(Self.row(report, "Antigravity", "five-hour")?.remainingPct, 90)
        XCTAssertEqual(Self.row(report, "Antigravity", "seven-day")?.remainingPct, 96)
        XCTAssertEqual(Self.row(report, "Muse", "seven-day")?.remainingPct, 97)
        XCTAssertEqual(Self.row(report, "Muse", "seven-day")?.resetAt, Date(timeIntervalSince1970: 1_792_720_686))

        let rolling = try XCTUnwrap(Self.row(report, "Notion", "rolling"))
        XCTAssertEqual(try XCTUnwrap(rolling.remainingPct), 96.8, accuracy: 0.001)
        XCTAssertEqual(rolling.windowDuration, 21_600)
        XCTAssertEqual(try XCTUnwrap(Self.row(report, "Notion", "monthly")?.remainingPct), 72.2, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Self.row(report, "Notion", "credits")?.remainingPct), 164.461017 / 3, accuracy: 0.001)

        // Kie and DeepSeek are balances, each under one API-billed row, with no quota window.
        for vendor in ["Kie", "DeepSeek", "OpenRouter"] {
            let rows = report.discoveredAgents.filter { $0.vendor == vendor }
            XCTAssertEqual(rows.count, 1, vendor)
            XCTAssertTrue(rows.allSatisfy(\.isAPIBilled), vendor)
            let billing = try XCTUnwrap(report.billing.first { $0.vendor == vendor })
            XCTAssertTrue(rows.allSatisfy(billing.contains), "\(vendor)'s balance is listed under its row")
            XCTAssertFalse(report.snapshots.contains { snapshot in rows.contains { $0.id == snapshot.agentId } })
        }
        let kie = try XCTUnwrap(report.billing.first { $0.vendor == "Kie" })
        XCTAssertEqual(kie.balances.first?.total, 854)
        XCTAssertEqual(kie.currency, "credits")
        let deepseek = try XCTUnwrap(report.billing.first { $0.vendor == "DeepSeek" })
        XCTAssertEqual(deepseek.currency, "CNY")
        XCTAssertEqual(deepseek.balances.first?.total, Decimal(string: "110.5"))
        XCTAssertEqual(deepseek.balances.first?.granted, 10)
        XCTAssertEqual(deepseek.balances.first?.toppedUp, Decimal(string: "100.5"))
        let openrouter = try XCTUnwrap(report.billing.first { $0.vendor == "OpenRouter" })
        XCTAssertEqual(openrouter.currency, "USD")
        XCTAssertEqual(openrouter.balances.first?.total, Decimal(string: "5.5"))

        XCTAssertEqual(report.subscriptions["Codex"], "prolite")
        XCTAssertEqual(report.subscriptions["Muse"], "Muse Free")
        XCTAssertEqual(report.codexResetCredits?.availableCount, 0)
        XCTAssertTrue(report.sessions.isEmpty)
        XCTAssertEqual(Set(report.discoveredAgents.map(\.source)), [DmitHubProvider.source])
    }

    func testStaleChannelKeepsItsValuesButIsHeldBack() async throws {
        let hub = Hub { _ in Data(Self.sample.utf8) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)

        XCTAssertTrue(report.readingIssues?["Codex"]?.reason.contains("登录凭据需要更新") == true)
        XCTAssertTrue(report.readingIssues?["Codex"]?.reason.contains("2026") == true)
        XCTAssertNil(report.readingIssues?["Claude"])
        XCTAssertEqual(Set(report.readingIssues?.keys ?? [:].keys), ["Codex"])
        let codex = try XCTUnwrap(report.accounts?["Codex"]?.first)
        XCTAssertNil(codex.quotaWindowIDs, "A failed channel must not retire the rows it had")
        XCTAssertEqual(codex.observedAt.timeIntervalSince1970,
                       try XCTUnwrap(DateParsing.iso8601("2026-10-15T06:10:49.063Z")?.timeIntervalSince1970), accuracy: 0.001)
        XCTAssertNotNil(report.accounts?["Notion"]?.first?.quotaWindowIDs)
        let row = try XCTUnwrap(report.discoveredAgents.first { $0.vendor == "Codex" })
        XCTAssertFalse(report.assess(.window(row), now: Self.now).showsLevel)
    }

    func testMissingValuesAreNotZero() async throws {
        let hub = Hub { _ in Data(#"""
        {"providers": {"muse": {"available": false, "account_key": "fixture-muse", "status": "error", "stale": true,
                                "error": "登录失效"}}}
        """#.utf8) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)
        XCTAssertTrue(report.snapshots.isEmpty)
        XCTAssertEqual(report.readingIssues?["Muse"], .readFailed("登录失效"))
    }

    func testAFailureWithinTheGraceKeepsTheLastReadingsAsTheyWere() async throws {
        let hub = Hub { _ in Data(Self.sample.utf8) }
        let clock = Clock()
        let provider = provider(hub, clock: clock)
        await provider.refreshAccountUsage(historyHours: 24)
        await hub.set { _ in throw ProviderHTTPError(status: 504) }
        clock.advance(DmitHubProvider.failureGrace - 10)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)

        XCTAssertEqual(Self.row(report, "Claude", ClaudeUsage.sessionRowId)?.remainingPct, 86)
        XCTAssertEqual(Set(report.readingIssues?.keys ?? [:].keys), ["Codex"], "only what the hub itself said")
        XCTAssertNil(report.billing.first?.readingIssue)
    }

    func testFailedRequestKeepsLastReadingAndMarksEveryVendor() async throws {
        let hub = Hub { _ in Data(Self.sample.utf8) }
        let clock = Clock()
        let provider = provider(hub, clock: clock)
        await provider.refreshAccountUsage(historyHours: 24)
        await hub.set { _ in throw ProviderHTTPError(status: 502) }
        clock.advance(DmitHubProvider.failureGrace)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)

        XCTAssertEqual(Self.row(report, "Claude", ClaudeUsage.sessionRowId)?.remainingPct, 86)
        XCTAssertEqual(Set(report.readingIssues?.keys ?? [:].keys), ["Claude", "Codex", "Antigravity", "Muse", "Notion", "Kie", "DeepSeek", "OpenRouter"])
        XCTAssertEqual(report.readingIssues?["Claude"]?.kind, .readFailed)
        XCTAssertEqual(report.billing.first?.readingIssue?.kind, .readFailed)

        // The next answer clears the failure.
        await hub.set { _ in Data(Self.sample.utf8) }
        await provider.refreshAccountUsage(historyHours: 24)
        let recovered = try await provider.fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(Set(recovered.readingIssues?.keys ?? [:].keys), ["Codex"])
    }

    func testAFailedRequestIsTriedAgainSoonAndTheReportReadAfter() async throws {
        let hub = Hub { _ in throw ProviderHTTPError(status: 504) }
        let clock = Clock()
        let provider = provider(hub, clock: clock, retryDelays: [0.05])
        await provider.refreshAccountUsage(historyHours: 24)
        let checks = await provider.sourceChecks()
        XCTAssertEqual(checks[""]?.count, 2, "the collector reads the report again after the retry")
        await hub.set { _ in Data(Self.sample.utf8) }
        try await Task.sleep(for: .milliseconds(400))
        let requests = await hub.requests.count
        XCTAssertEqual(requests, 2, "one retry, which succeeded and stopped there")
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(Self.row(report, "Claude", ClaudeUsage.sessionRowId)?.remainingPct, 86)
        let after = await provider.sourceChecks()
        XCTAssertTrue(after.isEmpty)
    }

    func testNoReadingYetShowsNoWindows() async throws {
        let hub = Hub { _ in throw ProviderHTTPError(status: 401) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)
        XCTAssertTrue(report.snapshots.isEmpty)
        XCTAssertTrue(report.discoveredAgents.isEmpty)
        XCTAssertNotNil(report.notice)
    }

    func testRequestsCarryAuthorizationAndRefreshAsksTheHubFirst() async throws {
        let hub = Hub { _ in Data(Self.sample.utf8) }
        let provider = provider(hub)
        try await provider.requestCollection()
        let requests = await hub.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://hub.example/quota/api/refresh", "https://hub.example/quota/api/quota"])
        XCTAssertEqual(Set(requests.map { $0.value(forHTTPHeaderField: "Authorization") }), ["Basic Zml4dHVyZQ=="])
    }

    func testWithoutAnAnswerReadsAgainOnTheHubsInterval() async {
        let provider = provider(Hub { _ in Data() })
        let due = await provider.accountChecks(since: ["": Self.now], spread: [:], now: Self.now)
        XCTAssertEqual(due[""], Self.now.addingTimeInterval(DmitHubProvider.readInterval))
        XCTAssertFalse(provider.seesLocalWork)
    }

    /// The sample's pass finished at 06:17:13Z; it was read 67 s later.
    private static let pass = DateParsing.iso8601("2026-10-17T06:17:13.471344+00:00")!

    func testReadsJustAfterTheHubsNextPass() async {
        let clock = Clock()
        let provider = provider(Hub { _ in Data(Self.sample.utf8) }, clock: clock)
        await provider.refreshAccountUsage(historyHours: 24)
        let due = await provider.accountChecks(since: ["": Self.now], spread: [:], now: Self.now)
        XCTAssertEqual(due[""], Self.pass.addingTimeInterval(DmitHubProvider.readInterval + DmitHubProvider.passMargin),
                       "on the hub's clock, sooner than an interval after this read")
    }

    func testALatePassIsLookedForSoonUntilTheHubHasStalled() async {
        let clock = Clock()
        let provider = provider(Hub { _ in Data(Self.sample.utf8) }, clock: clock)
        // Read again once the next pass was due, and the hub still answers with the old one.
        clock.advance(DmitHubProvider.readInterval)
        await provider.refreshAccountUsage(historyHours: 24)
        let late = await provider.accountChecks(since: ["": clock.now], spread: [:], now: clock.now)
        XCTAssertEqual(late[""], clock.now.addingTimeInterval(DmitHubProvider.lateLook))

        // An interval past the pass that never came, the hub counts as stalled.
        clock.advance(DmitHubProvider.readInterval)
        await provider.refreshAccountUsage(historyHours: 24)
        let stalled = await provider.accountChecks(since: ["": clock.now], spread: [:], now: clock.now)
        XCTAssertEqual(stalled[""], clock.now.addingTimeInterval(DmitHubProvider.readInterval))
    }

    func testFailedRequestsAreTriedAgainLaterEachTime() async throws {
        let hub = Hub { _ in throw ProviderHTTPError(status: 504) }
        let clock = Clock()
        let provider = provider(hub, clock: clock, retryDelays: [3600, 7200])
        var retries: [Date] = []
        for _ in 0..<3 {
            await provider.refreshAccountUsage(historyHours: 24)
            let checks = await provider.sourceChecks()
            retries.append(try XCTUnwrap(checks[""]?.first))
        }
        XCTAssertEqual(retries.map { $0.timeIntervalSince(clock.now) }, [3602, 7202, 7202], "the last delay repeats")
        let due = await provider.accountChecks(since: ["": clock.now], spread: [:], now: clock.now)
        XCTAssertEqual(due[""], clock.now.addingTimeInterval(7200 + DmitHubProvider.readInterval),
                       "the collector stands by behind the pending retry")

        // A success starts the delays over.
        await hub.set { _ in Data(Self.sample.utf8) }
        await provider.refreshAccountUsage(historyHours: 24)
        await hub.set { _ in throw ProviderHTTPError(status: 504) }
        await provider.refreshAccountUsage(historyHours: 24)
        let again = await provider.sourceChecks()
        XCTAssertEqual(again[""]?.first?.timeIntervalSince(clock.now), 3602)
    }

    func testSourceInfoCarriesBreakdownAndTopUp() throws {
        let quota = try DmitQuota.parse(Data(Self.sample.utf8))
        let claude = try XCTUnwrap(DmitHubProvider.sourceInfo(try XCTUnwrap(quota.channel("claude"))))
        XCTAssertTrue(claude.contains("Claude Code 83%"))
        XCTAssertTrue(claude.contains("Cowork 11%"))
        XCTAssertTrue(try XCTUnwrap(DmitHubProvider.sourceInfo(try XCTUnwrap(quota.channel("muse")))).contains("31B tokens left"))
        XCTAssertNil(DmitHubProvider.sourceInfo(try XCTUnwrap(quota.channel("kie"))))
    }

    func testTheAPISpendThisMonthIsShownWithClaudesAccount() async throws {
        let anthropic = #""anthropic": {"available": true, "account_key": "fixture-anthropic", "spend": {"available": true, "month_used": 12.34, "currency": "USD", "period_start": "2026-10-01T00:00:00Z", "resets_at": "2026-11-01T00:00:00Z"}, "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.416379+00:00"},"#
        let withSpend = Self.sample.replacingOccurrences(of: #""providers": {"#, with: #""providers": {"# + anthropic)
        let hub = Hub { _ in Data(withSpend.utf8) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)

        let wallet = try XCTUnwrap(report.accounts?["Claude"]?.first?.wallets?.first)
        XCTAssertEqual(wallet.kind, .monthlySpend)
        XCTAssertEqual(wallet.used, Decimal(string: "12.34"))
        XCTAssertEqual(wallet.currency, "USD")
        XCTAssertNil(report.accounts?["Codex"]?.first?.wallets, "only Claude's account carries it")
        XCTAssertFalse(report.discoveredAgents.contains { $0.vendor.lowercased() == "anthropic" }, "no row of its own")
        XCTAssertNil(report.readingIssues?["Anthropic"])

        // Before the hub has read it, Claude's account has no wallet rather than a spend of zero.
        let without = try await self.provider(Hub { _ in Data(Self.sample.utf8) }).fetchUsageAfterRefresh()
        XCTAssertNil(without.accounts?["Claude"]?.first?.wallets)
    }

    func testTheConsolesPrepaidBalanceIsItsOwnRing() async throws {
        let credits = #""anthropic_credits": {"available": true, "account_key": "fixture-console", "credits": {"available": true, "used": 22.62, "total": 100.0, "remaining": 77.38, "currency": "USD", "remaining_kind": "balance"}, "status": "fresh", "stale": false, "fetched_at": "2026-10-17T06:17:10.416379+00:00"},"#
        let sample = Self.sample.replacingOccurrences(of: #""providers": {"#, with: #""providers": {"# + credits)
        let report = try await provider(Hub { _ in Data(sample.utf8) }).fetchUsageAfterRefresh()

        XCTAssertNil(report.accounts?["Claude"]?.first?.wallets, "the balance is the Anthropic API's, not Claude's")
        XCTAssertFalse(report.billing.contains { $0.vendor.lowercased().hasPrefix("anthropic") }, "not a balance row of its own")

        // Its own mark: one ring, the balance as a share of the $100 limit, with the amount beside its windows.
        let rows = report.discoveredAgents.filter { $0.vendor == "Anthropic API" }
        XCTAssertEqual(rows.map(\.windowKey), ["balance"])
        XCTAssertEqual(try XCTUnwrap(Self.row(report, "Anthropic API", "balance")?.remainingPct), 77.38, accuracy: 0.001)
        XCTAssertEqual(report.accounts?["Anthropic API"]?.first?.wallets?.first?.balance, Decimal(string: "77.38"))
    }

    func testClaudesCloudCreditsAreAWindowOfClaudes() async throws {
        let cloud = #""breakdown": {"claude_code": 83, "chat": 6, "cowork": 11, "other": 0}, "cloud": {"used_pct": 45.5, "limit_dollars": 250.0, "used_dollars": 113.78, "remaining_dollars": 136.22, "resets_at": "2026-11-05T07:59:00+00:00"},"#
        let sample = Self.sample.replacingOccurrences(of: #""breakdown": {"claude_code": 83, "chat": 6, "cowork": 11, "other": 0},"#, with: cloud)
        XCTAssertNotEqual(sample, Self.sample)
        let report = try await provider(Hub { _ in Data(sample.utf8) }).fetchUsageAfterRefresh()

        let window = try XCTUnwrap(Self.row(report, "Claude", DmitQuota.cloudRowId))
        XCTAssertEqual(try XCTUnwrap(window.remainingPct), 54.5, accuracy: 0.001)
        XCTAssertEqual(window.resetAt, DateParsing.iso8601("2026-11-05T07:59:00Z"))
        XCTAssertNil(window.windowDuration, "a grant that expires, not a window that repeats")
        let row = try XCTUnwrap(report.discoveredAgents.first { $0.windowKey == DmitQuota.cloudRowId })
        XCTAssertEqual(row.vendor, "Claude")
        XCTAssertEqual(row.shortName, L10n.text("云端", "Cloud"))
        XCTAssertNotNil(Self.row(report, "Claude", ClaudeUsage.sessionRowId), "beside the plan's own windows")

        // A plan without the grant has no such window rather than one at 0 %.
        let plain = try await provider(Hub { _ in Data(Self.sample.utf8) }).fetchUsageAfterRefresh()
        XCTAssertNil(Self.row(plain, "Claude", DmitQuota.cloudRowId))
    }

    func testABalanceKeepsItsRowWhenTheHubReadsItUnderAnotherKey() throws {
        let read = try DmitQuota.parse(Data(Self.sample.utf8))
        let channel = try XCTUnwrap(read.channel("deepseek"))
        let signedOut = try DmitQuota.parse(Data(#"{"providers": {"deepseek": {"available": false, "account_key": "deepseek:signed-out"}}}"#.utf8))
        XCTAssertEqual(DmitHubProvider.pool(channel).id, DmitHubProvider.pool(try XCTUnwrap(signedOut.channel("deepseek"))).id)
        XCTAssertNotEqual(DmitHubProvider.pool(channel).id, DmitHubProvider.pool(try XCTUnwrap(read.channel("kie"))).id)
    }

    func testAccountIDsNeverCarryTheHubsKey() throws {
        let quota = try DmitQuota.parse(Data(Self.sample.utf8))
        let ids = DmitHubProvider.rows(quota).map(\.id)
        XCTAssertFalse(ids.contains { $0.contains("fixture") })
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testAntigravityQuotaWindowsMapAllModelGroups() async throws {
        let agyWindows = #"""
        "antigravity": {
          "available": true,
          "quota_windows": [
            {"id": "gemini-weekly", "group": "Gemini Models", "name": "Weekly Limit Remaining", "window_seconds": 604800, "used_percent": 3.0, "resets_at": "2026-10-31T09:40:56Z"},
            {"id": "gemini-5h", "group": "Gemini Models", "name": "Five Hour Limit Remaining", "window_seconds": 18000, "used_percent": 0.0, "resets_at": "2026-10-25T18:11:49Z"},
            {"id": "3p-weekly", "group": "Claude and GPT models", "name": "Weekly Limit Remaining", "window_seconds": 604800, "used_percent": 14.0, "resets_at": "2026-10-30T05:16:42Z"},
            {"id": "3p-5h", "group": "Claude and GPT models", "name": "Five Hour Limit Remaining", "window_seconds": 18000, "used_percent": 0.0, "resets_at": "2026-10-25T18:11:49Z"},
            {"id": "gemini-argon-wtu-weekly", "group": "Gemini 4 Argon", "name": "Gemini 4 Argon Weekly Limit", "window_seconds": 604800, "used_percent": 72.0, "resets_at": "2026-10-30T05:02:03Z"}
          ],
          "status": "fresh", "stale": false, "fetched_at": "2026-10-25T13:11:49Z"
        }
        """#
        let payload = #"{"updated_at": "2026-10-25T13:11:49Z", "providers": {\#(agyWindows)}}"#
        let report = try await provider(Hub { _ in Data(payload.utf8) }).fetchUsageAfterRefresh()
        let rows = report.discoveredAgents.filter { $0.vendor == "Antigravity" }
        XCTAssertEqual(rows.map(\.windowKey), [
            "antigravity:gemini-weekly",
            "antigravity:gemini-5h",
            "antigravity:3p-weekly",
            "antigravity:3p-5h",
            "antigravity:gemini-argon-wtu-weekly"
        ])
        XCTAssertEqual(Set(rows.map(\.shortName)).count, 5, "all 5 Antigravity buckets must have distinct short names")
        XCTAssertEqual(Self.row(report, "Antigravity", "antigravity:gemini-weekly")?.remainingPct, 97)
        XCTAssertEqual(Self.row(report, "Antigravity", "antigravity:3p-weekly")?.remainingPct, 86)
        XCTAssertEqual(Self.row(report, "Antigravity", "antigravity:gemini-argon-wtu-weekly")?.remainingPct, 28)
    }
}

private extension DmitHubProvider {
    func fetchUsageAfterRefresh() async throws -> UsageReport {
        await refreshAccountUsage(historyHours: 24)
        return try await fetchUsage(agents: [], historyHours: 24)
    }
}
