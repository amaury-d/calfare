import XCTest
@testable import CalflareCore

final class CalendarToggleTests: XCTestCase {
    private let available = [
        AvailableCalendar(identifier: "a", title: "Work", sourceTitle: "Exchange"),
        AvailableCalendar(identifier: "b", title: "Perso", sourceTitle: "iCloud"),
        AvailableCalendar(identifier: "c", title: "Famille", sourceTitle: "iCloud")
    ]

    func testUncheckingWhileAllMaterializesTheRest() {
        XCTAssertEqual(
            CalendarToggle.setting(false, for: "b", in: .all, available: available),
            .identifiers(["a", "c"])
        )
    }

    func testCheckingWhileAllIsANoOp() {
        XCTAssertEqual(CalendarToggle.setting(true, for: "b", in: .all, available: available), .all)
    }

    func testAddAndRemoveWithinIdentifiers() {
        var selection = CalendarSelection.identifiers(["a"])
        selection = CalendarToggle.setting(true, for: "b", in: selection, available: available)
        XCTAssertEqual(selection, .identifiers(["a", "b"]))
        selection = CalendarToggle.setting(false, for: "a", in: selection, available: available)
        selection = CalendarToggle.setting(false, for: "b", in: selection, available: available)
        XCTAssertEqual(selection, .identifiers([]))
    }

    func testUnavailableIdentifiersSurviveToggles() {
        let selection = CalendarToggle.setting(
            true, for: "a", in: .identifiers(["offline"]), available: available
        )
        XCTAssertEqual(selection, .identifiers(["offline", "a"]))
    }

    func testSettingAll() {
        XCTAssertEqual(CalendarToggle.settingAll(true), .all)
        XCTAssertEqual(CalendarToggle.settingAll(false), .identifiers([]))
    }

    func testIsAllSelectedOnlyForAll() {
        XCTAssertTrue(CalendarToggle.isAllSelected(.all))
        XCTAssertFalse(CalendarToggle.isAllSelected(.identifiers(["a", "b", "c"])))
        XCTAssertTrue(CalendarToggle.isSelected("zzz", in: .all))
        XCTAssertFalse(CalendarToggle.isSelected("zzz", in: .identifiers(["a"])))
    }

    func testGroupingBreaksTitleTiesByIdentifier() {
        let calendars = [
            AvailableCalendar(identifier: "z", title: "Work", sourceTitle: "Exchange"),
            AvailableCalendar(identifier: "a", title: "Work", sourceTitle: "Exchange")
        ]
        XCTAssertEqual(groupCalendarsBySource(calendars)[0].calendars.map(\.identifier), ["a", "z"])
        XCTAssertTrue(groupCalendarsBySource([]).isEmpty)
    }

    func testTogglingUnknownIdentifierWhileAllStillExcludesOnlyIt() {
        XCTAssertEqual(
            CalendarToggle.setting(false, for: "ghost", in: .all, available: available),
            .identifiers(["a", "b", "c"])
        )
    }

    func testGroupingOrdersAccountsThenCalendars() {
        let calendars = [
            AvailableCalendar(identifier: "1", title: "Zèbre", sourceTitle: "iCloud"),
            AvailableCalendar(identifier: "2", title: "Agenda", sourceTitle: "iCloud"),
            AvailableCalendar(identifier: "3", title: "Work", sourceTitle: "Exchange"),
            AvailableCalendar(identifier: "4", title: "Work", sourceTitle: "Google"),
            AvailableCalendar(identifier: "5", title: "Orphan")
        ]
        let groups = groupCalendarsBySource(calendars)
        XCTAssertEqual(groups.map(\.sourceTitle), ["", "Exchange", "Google", "iCloud"])
        XCTAssertEqual(groups[3].calendars.map(\.title), ["Agenda", "Zèbre"])
    }
}
