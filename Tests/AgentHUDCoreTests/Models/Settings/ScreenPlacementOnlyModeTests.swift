import Foundation
import XCTest
@testable import AgentHUDCore

final class ScreenPlacementOnlyModeTests: XCTestCase {
    override func setUp() { ScreenPlacement.onlyMode = .simple }
    override func tearDown() { ScreenPlacement.onlyMode = nil }

    func testEveryDisplayStartsSimpleOnTheLeft() {
        for hasNotch in [true, false] {
            let placement = ScreenPlacement.default(hasNotch: hasNotch)
            XCTAssertEqual(placement.mode, .simple)
            XCTAssertEqual(placement.edge, .left)
        }
    }

    func testSavedModesReadAsSimple() throws {
        let notch = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"notch","edge":"top"}"#.utf8))
        XCTAssertEqual(notch.mode, .simple)
        XCTAssertEqual(notch.edge, .left, "a screen saved at the notch had no edge of its own")
        let logos = try JSONDecoder().decode(ScreenPlacement.self, from: Data(#"{"mode":"logos","edge":"right"}"#.utf8))
        XCTAssertEqual(logos.mode, .simple)
        XCTAssertEqual(logos.edge, .right, "a docked screen keeps the edge it was on")
    }

    func testNoChangeOrProposalLeavesSimple() {
        var placement = ScreenPlacement(mode: .notch)
        XCTAssertEqual(placement.mode, .simple)
        placement.mode = .logos
        XCTAssertEqual(placement.mode, .simple)
        XCTAssertEqual(HUDStyle(mode: .notch).applied(to: ScreenPlacement()).mode, .simple, "an agent's proposal")
    }

    func testWithoutALockEachScreenKeepsItsOwn() {
        ScreenPlacement.onlyMode = nil
        XCTAssertEqual(ScreenPlacement.default(hasNotch: true).mode, .notch)
        XCTAssertEqual(ScreenPlacement(mode: .logos).mode, .logos)
    }
}
