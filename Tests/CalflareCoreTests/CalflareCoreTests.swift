import Foundation
import XCTest
@testable import CalflareCore

final class CalflareCoreTests: XCTestCase {
    func testAlertWindowEdgesAndExcludedEvents() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(45)), now: now))
        XCTAssertTrue(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(85)), now: now))
        for seconds in [44.9, 85.1] {
            XCTAssertFalse(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(seconds)), now: now))
        }
        XCTAssertFalse(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(60), isAllDay: true), now: now))
        XCTAssertFalse(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(60), isCancelled: true), now: now))
        XCTAssertFalse(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(60), isDeclined: true), now: now))
        XCTAssertFalse(EventEligibility.shouldAlert(.init(start: now.addingTimeInterval(60), title: "Declined: Review"), now: now))
    }

    func testDeduplicationKeysAndExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let current = EventDeduplication.key(start: now, identifier: "occurrence")
        let expired = EventDeduplication.key(start: now.addingTimeInterval(-EventDeduplication.retention - 1), identifier: "old")
        XCTAssertEqual(current, "1000000|occurrence")
        XCTAssertEqual(EventDeduplication.retainedKeys([current, expired, "bad-key"], now: now), [current])
    }

    func testTeamsURLExtraction() {
        XCTAssertEqual(
            TeamsLink.extract(from: "Join https://teams.microsoft.com/l/meetup/abc?x=1&y=2>"),
            "https://teams.microsoft.com/l/meetup/abc?x=1&y=2"
        )
        XCTAssertEqual(TeamsLink.extract(from: "https://teams.live.com/meet/abc"), "https://teams.live.com/meet/abc")
        XCTAssertNil(TeamsLink.extract(from: "https://zoom.us/j/123"))
    }

    func testCalendarSelectionUsesIdentifiersNotNames() {
        let calendars = [
            AvailableCalendar(identifier: "one", title: "Work"),
            AvailableCalendar(identifier: "two", title: "Work")
        ]
        let result = selectCalendars(calendars, using: .identifiers(["two", "missing"]))
        XCTAssertEqual(result.selected.map(\.identifier), ["two"])
        XCTAssertEqual(result.unavailableIdentifiers, ["missing"])
        XCTAssertTrue(selectCalendars(calendars, using: .identifiers([])).selected.isEmpty)
        XCTAssertEqual(selectCalendars(calendars, using: .all).selected, calendars)
        let missing = selectCalendars(calendars, using: .identifiers(["missing"]))
        XCTAssertTrue(missing.selected.isEmpty)
        XCTAssertEqual(missing.unavailableIdentifiers, ["missing"])
    }

    func testConfigurationMissingEmptyAndInvalid() throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .all)
        try Data("{}".utf8).write(to: url)
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .all)
        try Data(#"{"calendarIdentifiers":["one","two"]}"#.utf8).write(to: url)
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .identifiers(["one", "two"]))
        try Data(#"{"calendarIdentifiers":[]}"#.utf8).write(to: url)
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .identifiers([]))
        try Data(#"{"calendarIdentifiers":"not-an-array"}"#.utf8).write(to: url)
        XCTAssertThrowsError(try CalendarConfiguration.load(from: url)) {
            XCTAssertEqual($0 as? CalendarConfigurationError, .invalidIdentifiers)
        }
        try Data("{".utf8).write(to: url)
        XCTAssertThrowsError(try CalendarConfiguration.load(from: url)) {
            XCTAssertEqual($0 as? CalendarConfigurationError, .invalidJSON)
        }
    }
}
