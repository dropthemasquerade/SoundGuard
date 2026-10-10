import XCTest
@testable import SoundGuard

final class MonitoringWindowTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testDisabledWindowIsAlwaysOpen() {
        let window = MonitoringWindow(enabled: false, startMinutes: 22 * 60, endMinutes: 7 * 60)
        XCTAssertTrue(window.contains(date(hour: 3), calendar: calendar))
        XCTAssertTrue(window.contains(date(hour: 15), calendar: calendar))
        XCTAssertNil(window.secondsUntilBoundary(from: date(hour: 3), calendar: calendar))
    }

    func testEqualEndpointsStayOpenAllDay() {
        let window = MonitoringWindow(enabled: true, startMinutes: 9 * 60, endMinutes: 9 * 60)
        XCTAssertTrue(window.contains(date(hour: 8, minute: 59), calendar: calendar))
        XCTAssertTrue(window.contains(date(hour: 9), calendar: calendar))
        XCTAssertNil(window.secondsUntilBoundary(from: date(hour: 9), calendar: calendar))
    }

    func testDaytimeWindowIsHalfOpen() {
        let window = MonitoringWindow(enabled: true, startMinutes: 8 * 60, endMinutes: 22 * 60)
        XCTAssertTrue(window.contains(date(hour: 8), calendar: calendar))
        XCTAssertTrue(window.contains(date(hour: 21, minute: 59), calendar: calendar))
        XCTAssertFalse(window.contains(date(hour: 22), calendar: calendar))
        XCTAssertFalse(window.contains(date(hour: 7, minute: 59), calendar: calendar))
    }

    func testOvernightWindowWrapsPastMidnight() {
        let window = MonitoringWindow(enabled: true, startMinutes: 22 * 60, endMinutes: 7 * 60)
        XCTAssertTrue(window.contains(date(hour: 22), calendar: calendar))
        XCTAssertTrue(window.contains(date(hour: 23, minute: 30), calendar: calendar))
        XCTAssertTrue(window.contains(date(hour: 0, minute: 15), calendar: calendar))
        XCTAssertTrue(window.contains(date(hour: 6, minute: 59), calendar: calendar))
        XCTAssertFalse(window.contains(date(hour: 7), calendar: calendar))
        XCTAssertFalse(window.contains(date(hour: 12), calendar: calendar))
        XCTAssertEqual(window.label, "22:00–07:00")
    }

    func testSecondsUntilTheNextEdge() {
        let window = MonitoringWindow(enabled: true, startMinutes: 8 * 60, endMinutes: 22 * 60)
        let inside = date(hour: 21, minute: 30)
        XCTAssertEqual(window.secondsUntilBoundary(from: inside, calendar: calendar), 30 * 60)
        let outside = date(hour: 23)
        XCTAssertEqual(window.secondsUntilBoundary(from: outside, calendar: calendar), 9 * 60 * 60)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: hour, minute: minute))!
    }
}
