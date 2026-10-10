import XCTest
@testable import SoundGuard

final class NotificationPresetTests: XCTestCase {
    func testCatalogCoversClassicMessageAlerts() {
        let names = NotificationPreset.catalog.map(\.name)
        XCTAssertEqual(names, ["Zoom", "Slack", "Telegram", "WeChat", "QQ", "iPhone"])
        let ids = Set(NotificationPreset.catalog.map(\.id))
        XCTAssertEqual(ids.count, NotificationPreset.catalog.count)
        for preset in NotificationPreset.catalog {
            XCTAssertFalse(preset.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, preset.name)
            XCTAssertFalse(preset.hint.isEmpty, preset.name)
        }
    }
}
