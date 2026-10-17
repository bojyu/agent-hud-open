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

    private func provider(_ hub: Hub, authorization: String? = "Basic Zml4dHVyZQ==") -> DmitHubProvider {
        DmitHubProvider(base: URL(string: "https://hub.example/quota/")!, authorization: { authorization },
                        http: ProviderHTTP(send: { try await hub.respond($0) }), clock: { Self.now })
    }

    private static func row(_ report: UsageReport, _ vendor: String, _ window: String) -> UsageSnapshot? {
        report.snapshots.first { snapshot in
            report.discoveredAgents.contains { $0.id == snapshot.agentId && $0.vendor == vendor && $0.windowKey == window }
        }
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

        // Kie is a balance in credits, not a quota window.
        XCTAssertNil(report.discoveredAgents.first { $0.vendor == "Kie" })
        XCTAssertEqual(report.billing.first?.vendor, "Kie")
        XCTAssertEqual(report.billing.first?.balances.first?.total, 854)
        XCTAssertEqual(report.billing.first?.currency, "credits")

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

        XCTAssertEqual(report.readingIssues?["Codex"], .readFailed("登录凭据需要更新"))
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

    func testFailedRequestKeepsLastReadingAndMarksEveryVendor() async throws {
        let hub = Hub { _ in Data(Self.sample.utf8) }
        let provider = provider(hub)
        await provider.refreshAccountUsage(historyHours: 24)
        await hub.set { _ in throw ProviderHTTPError(status: 502) }
        await provider.refreshAccountUsage(historyHours: 24)
        let report = try await provider.fetchUsage(agents: [], historyHours: 24)

        XCTAssertEqual(Self.row(report, "Claude", ClaudeUsage.sessionRowId)?.remainingPct, 86)
        XCTAssertEqual(Set(report.readingIssues?.keys ?? [:].keys), ["Claude", "Codex", "Antigravity", "Muse", "Notion", "Kie"])
        XCTAssertEqual(report.readingIssues?["Claude"]?.kind, .readFailed)
        XCTAssertEqual(report.billing.first?.readingIssue?.kind, .readFailed)

        // The next answer clears the failure.
        await hub.set { _ in Data(Self.sample.utf8) }
        await provider.refreshAccountUsage(historyHours: 24)
        let recovered = try await provider.fetchUsage(agents: [], historyHours: 24)
        XCTAssertEqual(Set(recovered.readingIssues?.keys ?? [:].keys), ["Codex"])
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

    func testReadsAgainOnTheHubsInterval() async {
        let provider = provider(Hub { _ in Data() })
        let last = Self.now
        let due = await provider.accountChecks(since: ["": last], spread: [:], now: Self.now)
        XCTAssertEqual(due[""], last.addingTimeInterval(DmitHubProvider.readInterval))
        XCTAssertFalse(provider.seesLocalWork)
    }

    func testSourceInfoCarriesBreakdownAndTopUp() throws {
        let quota = try DmitQuota.parse(Data(Self.sample.utf8))
        let claude = try XCTUnwrap(DmitHubProvider.sourceInfo(try XCTUnwrap(quota.channel("claude"))))
        XCTAssertTrue(claude.contains("Claude Code 83%"))
        XCTAssertTrue(claude.contains("Cowork 11%"))
        XCTAssertTrue(try XCTUnwrap(DmitHubProvider.sourceInfo(try XCTUnwrap(quota.channel("muse")))).contains("31B tokens left"))
        XCTAssertNil(DmitHubProvider.sourceInfo(try XCTUnwrap(quota.channel("kie"))))
    }

    func testAccountIDsNeverCarryTheHubsKey() throws {
        let quota = try DmitQuota.parse(Data(Self.sample.utf8))
        let ids = DmitHubProvider.rows(quota).map(\.id)
        XCTAssertFalse(ids.contains { $0.contains("fixture") })
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
