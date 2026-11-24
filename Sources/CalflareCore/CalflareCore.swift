import Foundation

public enum CalendarSelection: Equatable {
    case all
    case identifiers(Set<String>)
}

public enum CalendarConfigurationError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case invalidJSON
    case invalidIdentifiers
    case unwritable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "Cannot read calendar configuration: \(reason)"
        case .invalidJSON: return "config.json must contain a JSON object."
        case .invalidIdentifiers:
            return "calendarIdentifiers must be an array of non-empty strings (an empty array selects no calendars)."
        case .unwritable(let reason): return "Cannot write calendar configuration: \(reason)"
        }
    }
}

public enum CalendarConfiguration {
    public static func load(from url: URL) throws -> CalendarSelection {
        guard FileManager.default.fileExists(atPath: url.path) else { return .all }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CalendarConfigurationError.unreadable(error.localizedDescription)
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CalendarConfigurationError.invalidJSON
        }
        guard let object = value as? [String: Any] else {
            throw CalendarConfigurationError.invalidJSON
        }
        guard let rawIdentifiers = object["calendarIdentifiers"] else { return .all }
        guard let identifiers = rawIdentifiers as? [Any],
              identifiers.allSatisfy({ value in
                  guard let identifier = value as? String else { return false }
                  return !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw CalendarConfigurationError.invalidIdentifiers
        }
        return .identifiers(Set(identifiers.compactMap { $0 as? String }))
    }

    /// Merges `selection` into the bytes of an existing configuration and returns the bytes to
    /// write. `existing` is nil when no configuration file is present.
    ///
    /// Unknown top-level keys are preserved. `.all` removes `calendarIdentifiers` entirely,
    /// because a missing key means "every calendar"; `retained` is ignored in that case.
    /// Identifiers in `retained` are kept so that a calendar belonging to a temporarily
    /// unavailable account is not silently dropped.
    public static func configurationData(
        for selection: CalendarSelection,
        existing: Data?,
        retainingUnavailable retained: Set<String> = []
    ) throws -> Data {
        var object: [String: Any] = [:]
        if let existing, !existing.isEmpty {
            // Refuse to clobber a file we cannot understand: the user may be editing it.
            guard let value = try? JSONSerialization.jsonObject(with: existing),
                  let existingObject = value as? [String: Any] else {
                throw CalendarConfigurationError.invalidJSON
            }
            object = existingObject
        }
        switch selection {
        case .all:
            object.removeValue(forKey: "calendarIdentifiers")
        case .identifiers(let identifiers):
            object["calendarIdentifiers"] = identifiers.union(retained).sorted()
        }
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            throw CalendarConfigurationError.unwritable(error.localizedDescription)
        }
        return data + Data("\n".utf8)
    }

    /// Reads the current configuration, merges `selection` into it, and replaces the file
    /// atomically so a concurrent reader never observes a partial write.
    public static func save(
        _ selection: CalendarSelection,
        to url: URL,
        retainingUnavailable retained: Set<String> = []
    ) throws {
        var existing: Data?
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                existing = try Data(contentsOf: url)
            } catch {
                throw CalendarConfigurationError.unreadable(error.localizedDescription)
            }
        }
        let data = try configurationData(
            for: selection, existing: existing, retainingUnavailable: retained
        )
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw CalendarConfigurationError.unwritable(error.localizedDescription)
        }
    }
}

public struct AvailableCalendar: Equatable {
    public let identifier: String
    public let title: String
    public let sourceTitle: String

    public init(identifier: String, title: String, sourceTitle: String = "") {
        self.identifier = identifier
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

public struct CalendarGroup: Equatable {
    public let sourceTitle: String
    public let calendars: [AvailableCalendar]

    public init(sourceTitle: String, calendars: [AvailableCalendar]) {
        self.sourceTitle = sourceTitle
        self.calendars = calendars
    }
}

/// Groups calendars by account for display, sorted by account then calendar title.
public func groupCalendarsBySource(_ calendars: [AvailableCalendar]) -> [CalendarGroup] {
    let order: (AvailableCalendar, AvailableCalendar) -> Bool = { left, right in
        switch left.title.localizedStandardCompare(right.title) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return left.identifier < right.identifier
        }
    }
    return Dictionary(grouping: calendars, by: \.sourceTitle)
        .map { CalendarGroup(sourceTitle: $0.key, calendars: $0.value.sorted(by: order)) }
        .sorted { left, right in
            switch left.sourceTitle.localizedStandardCompare(right.sourceTitle) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return false
            }
        }
}

public enum CalendarToggle {
    public static func isSelected(_ identifier: String, in selection: CalendarSelection) -> Bool {
        switch selection {
        case .all: return true
        case .identifiers(let identifiers): return identifiers.contains(identifier)
        }
    }

    /// True only for `.all`. An explicit list that happens to cover every available calendar
    /// is not "all", because the two differ for calendars added later.
    public static func isAllSelected(_ selection: CalendarSelection) -> Bool {
        selection == .all
    }

    public static func setting(
        _ isOn: Bool,
        for identifier: String,
        in selection: CalendarSelection,
        available: [AvailableCalendar]
    ) -> CalendarSelection {
        switch selection {
        case .all:
            guard !isOn else { return .all }
            // Materialize the implicit "all" into the calendars that exist right now.
            return .identifiers(Set(available.map(\.identifier)).subtracting([identifier]))
        case .identifiers(let identifiers):
            return .identifiers(isOn ? identifiers.union([identifier])
                                     : identifiers.subtracting([identifier]))
        }
    }

    public static func settingAll(
        _ isOn: Bool,
        available: [AvailableCalendar] = []
    ) -> CalendarSelection {
        isOn ? .all : .identifiers([])
    }
}

public struct CalendarSelectionResult: Equatable {
    public let selected: [AvailableCalendar]
    public let unavailableIdentifiers: Set<String>
}

public func selectCalendars(
    _ calendars: [AvailableCalendar],
    using selection: CalendarSelection
) -> CalendarSelectionResult {
    guard case .identifiers(let identifiers) = selection else {
        return CalendarSelectionResult(selected: calendars, unavailableIdentifiers: [])
    }
    let selected = calendars.filter { identifiers.contains($0.identifier) }
    let availableIdentifiers = Set(calendars.map(\.identifier))
    return CalendarSelectionResult(
        selected: selected,
        unavailableIdentifiers: identifiers.subtracting(availableIdentifiers)
    )
}

public struct CalendarEvent: Equatable {
    public let start: Date
    public let isAllDay: Bool
    public let isCancelled: Bool
    public let isDeclined: Bool
    public let title: String

    public init(
        start: Date,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        title: String = ""
    ) {
        self.start = start
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.title = title
    }
}

public enum EventEligibility {
    public static func shouldAlert(_ event: CalendarEvent, now: Date) -> Bool {
        let seconds = event.start.timeIntervalSince(now)
        let title = event.title.lowercased()
        let declinedOrCancelledTitle = [
            "declined:", "canceled:", "cancelled:", "refusé", "annulé"
        ].contains(where: title.hasPrefix)
        return !event.isAllDay && !event.isCancelled && !event.isDeclined
            && !declinedOrCancelledTitle && seconds >= 45 && seconds <= 85
    }
}

public enum EventDeduplication {
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    public static func key(start: Date, identifier: String) -> String {
        "\(Int(start.timeIntervalSince1970))|\(identifier)"
    }

    public static func retainedKeys(_ keys: [String], now: Date) -> [String] {
        let cutoff = Int(now.timeIntervalSince1970 - retention)
        return keys.filter {
            guard let epoch = Int($0.split(separator: "|", maxSplits: 1).first ?? "") else {
                return false
            }
            return epoch >= cutoff
        }
    }
}

public enum TeamsLink {
    public static func extract(from text: String) -> String? {
        let pattern = #"https://teams\.(microsoft|live)\.com/[^\s<>"']+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
