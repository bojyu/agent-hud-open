import Foundation
import XCTest
@testable import AgentHUDCore

final class HUDDisplaySettingTests: XCTestCase {
    func testTheChosenDisplayIsSavedAndReadBack() throws {
        for choice in [nil, Settings.hudDisplayAll, "37D8832A-2D66-02CA-B9F7-8F30A301B230"] {
            var settings = Settings()
            settings.hudDisplay = choice
            let read = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
            XCTAssertEqual(read.hudDisplay, choice)
        }
    }

    func testSettingsSavedBeforeTheChoiceTakeTheDefault() throws {
        let read = try JSONDecoder().decode(Settings.self, from: Data(#"{"showMenuBarIcon":true}"#.utf8))
        XCTAssertNil(read.hudDisplay)
        let written = try XCTUnwrap(String(data: JSONEncoder().encode(Settings()), encoding: .utf8))
        XCTAssertFalse(written.contains("hudDisplay"), "the default is left out, as it was before the choice existed")
    }
}
