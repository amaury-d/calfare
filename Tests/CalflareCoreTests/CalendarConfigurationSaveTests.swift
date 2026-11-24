import Foundation
import XCTest
@testable import CalflareCore

final class CalendarConfigurationSaveTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".test-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPreservesUnknownTopLevelKeys() throws {
        let existing = Data(#"{"future":{"a":1},"calendarIdentifiers":["x"]}"#.utf8)
        let data = try CalendarConfiguration.configurationData(
            for: .identifiers(["y"]), existing: existing, retainingUnavailable: []
        )
        let object = try json(data)
        XCTAssertEqual(object["calendarIdentifiers"] as? [String], ["y"])
        XCTAssertEqual((object["future"] as? [String: Int])?["a"], 1)
    }

    func testAllRemovesTheKeyAndRoundTrips() throws {
        let url = try makeDirectory().appendingPathComponent("config.json")
        try CalendarConfiguration.save(.identifiers(["a"]), to: url)
        try CalendarConfiguration.save(.all, to: url)
        XCTAssertNil(try json(Data(contentsOf: url))["calendarIdentifiers"])
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .all)
    }

    func testEmptySelectionWritesEmptyArray() throws {
        let url = try makeDirectory().appendingPathComponent("config.json")
        try CalendarConfiguration.save(.identifiers([]), to: url)
        XCTAssertEqual(try json(Data(contentsOf: url))["calendarIdentifiers"] as? [String], [])
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .identifiers([]))
    }

    func testRetainsUnavailableIdentifiers() throws {
        let data = try CalendarConfiguration.configurationData(
            for: .identifiers(["a"]), existing: nil, retainingUnavailable: ["offline"]
        )
        XCTAssertEqual(try json(data)["calendarIdentifiers"] as? [String], ["a", "offline"])
        let none = try CalendarConfiguration.configurationData(
            for: .identifiers([]), existing: nil, retainingUnavailable: []
        )
        XCTAssertEqual(try json(none)["calendarIdentifiers"] as? [String], [])
    }

    func testAllIgnoresRetainedIdentifiers() throws {
        let data = try CalendarConfiguration.configurationData(
            for: .all, existing: nil, retainingUnavailable: ["offline"]
        )
        XCTAssertNil(try json(data)["calendarIdentifiers"])
    }

    func testRefusesInvalidExistingFileAndLeavesItUntouched() throws {
        let url = try makeDirectory().appendingPathComponent("config.json")
        for content in ["{", "[]"] {
            try Data(content.utf8).write(to: url)
            XCTAssertThrowsError(try CalendarConfiguration.save(.identifiers(["a"]), to: url)) {
                XCTAssertEqual($0 as? CalendarConfigurationError, .invalidJSON)
            }
            XCTAssertEqual(try Data(contentsOf: url), Data(content.utf8))
        }
    }

    func testCreatesMissingDirectoryAndWritesSortedPrettyJSON() throws {
        let url = try makeDirectory().appendingPathComponent("nested/config.json")
        try CalendarConfiguration.save(.identifiers(["b", "a"]), to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertTrue(text.contains("\n"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "\"a\"")).lowerBound,
                          try XCTUnwrap(text.range(of: "\"b\"")).lowerBound)
    }

    func testEmptyExistingFileIsTreatedAsMissing() throws {
        let data = try CalendarConfiguration.configurationData(
            for: .identifiers(["a"]), existing: Data(), retainingUnavailable: []
        )
        XCTAssertEqual(try json(data)["calendarIdentifiers"] as? [String], ["a"])
    }

    func testSaveIntoUnwritableLocationThrowsUnwritable() throws {
        let directory = try makeDirectory()
        let blocker = directory.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        // A regular file cannot act as the parent directory of config.json.
        let url = blocker.appendingPathComponent("config.json")
        XCTAssertThrowsError(try CalendarConfiguration.save(.all, to: url)) {
            guard case .unwritable = $0 as? CalendarConfigurationError else {
                return XCTFail("expected .unwritable, got \($0)")
            }
        }
    }

    func testSaveReplacesExistingSelectionWithoutKeepingStaleIdentifiers() throws {
        let url = try makeDirectory().appendingPathComponent("config.json")
        try Data(#"{"calendarIdentifiers":["old"]}"#.utf8).write(to: url)
        try CalendarConfiguration.save(.identifiers(["new"]), to: url)
        XCTAssertEqual(try CalendarConfiguration.load(from: url), .identifiers(["new"]))
    }

    func testConfigurationDataRoundTripsThroughLoad() throws {
        let url = try makeDirectory().appendingPathComponent("config.json")
        for selection in [CalendarSelection.all, .identifiers([]), .identifiers(["a", "b"])] {
            try CalendarConfiguration.configurationData(
                for: selection, existing: nil, retainingUnavailable: []
            ).write(to: url)
            XCTAssertEqual(try CalendarConfiguration.load(from: url), selection)
        }
    }
}
