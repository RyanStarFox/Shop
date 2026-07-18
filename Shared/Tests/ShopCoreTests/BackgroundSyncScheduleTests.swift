import XCTest
@testable import ShopCore

final class BackgroundSyncScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: hour, minute: minute))!
    }

    func testDaytimeRequestsOneHour() {
        let noon = date(hour: 12)
        let next = BackgroundSyncSchedule.nextEarliestBeginDate(after: noon, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.hour], from: noon, to: next).hour, 1)
    }

    func testNightRequestsThreeHours() {
        let night = date(hour: 23)
        let next = BackgroundSyncSchedule.nextEarliestBeginDate(after: night, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.hour], from: night, to: next).hour, 3)
    }

    func testBoundary0700IsDay() {
        let boundary = date(hour: 7)
        let next = BackgroundSyncSchedule.nextEarliestBeginDate(after: boundary, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.hour], from: boundary, to: next).hour, 1)
    }

    func testBoundary2200IsNight() {
        let boundary = date(hour: 22)
        let next = BackgroundSyncSchedule.nextEarliestBeginDate(after: boundary, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.hour], from: boundary, to: next).hour, 3)
    }
}
