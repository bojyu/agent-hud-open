import Foundation
import XCTest
@testable import AgentHUDCore

final class VendorQuotaSummaryTests: XCTestCase {
    func testOneSummaryPerMarkShowingItsMostUsedWindowAndKeepingEveryRow() {
        let now = Date()
        func agent(_ id: String, _ vendor: String) -> AgentDescriptor {
            AgentDescriptor(id: id, vendor: vendor, model: id, source: "test", enabled: true)
        }
        let agents = [agent("codex-5h", "Codex"), agent("chatgpt", "ChatGPT"), agent("kimi", "Kimi"), agent("codex-week", "Codex")]
        let report = UsageReport(generatedAt: now, snapshots: [
            .init(agentId: "codex-5h", remainingPct: 82, resetAt: now.addingTimeInterval(3600), windowDuration: 5.0 * 3600, updatedAt: now),
            .init(agentId: "codex-week", remainingPct: 40, resetAt: now.addingTimeInterval(86400), windowDuration: 7.0 * 86400, updatedAt: now),
        ], sessions: [])
        let view = ReportView(report: report, agents: agents, settings: Settings(), now: now)

        let summaries = VendorQuotaSummary.summaries(rows: view.rows)

        XCTAssertEqual(summaries.map(\.markKey), ["ChatGPT", "Kimi"], "Codex and ChatGPT share one mark, in row order")
        XCTAssertEqual(summaries[0].vendor, "Codex", "named by the first vendor seen under the mark")
        XCTAssertEqual(summaries[0].rows.count, 3, "every row under the mark is kept for the details")
        XCTAssertEqual(summaries.map(\.usedPct), [60, nil])
        XCTAssertEqual(summaries[0].shownRowID, "codex-week")
        XCTAssertNil(summaries[1].level, "a window with no reading has no level")
    }

    func testAPinnedWindowIsShownEvenWhenAnotherIsMoreUsed() {
        let now = Date()
        func agent(_ id: String) -> AgentDescriptor {
            AgentDescriptor(id: id, vendor: "Notion", model: id, source: "test", enabled: true)
        }
        let agents = [agent("rolling"), agent("monthly")]
        let report = UsageReport(generatedAt: now, snapshots: [
            .init(agentId: "rolling", remainingPct: 10, resetAt: now.addingTimeInterval(3600), windowDuration: 6.0 * 3600, updatedAt: now),
            .init(agentId: "monthly", remainingPct: 70, resetAt: now.addingTimeInterval(86400 * 10), windowDuration: 30.0 * 86400, updatedAt: now),
        ], sessions: [])
        let view = ReportView(report: report, agents: agents, settings: Settings(), now: now)

        XCTAssertEqual(VendorQuotaSummary.summaries(rows: view.rows).map(\.usedPct), [30], "Notion's monthly allowance")
    }

    func testABasicHeaderEncodesItsUserAndPassword() {
        XCTAssertEqual(DmitHubProvider.basicAuthorization(user: "me", password: "pa:ss"), "Basic bWU6cGE6c3M=")
    }
}
