import Foundation

public enum CalendarSelection: Equatable {
    case all
    case identifiers(Set<String>)
}

public enum CalendarConfigurationError: Error, Equatable, LocalizedError {
    case unreadable(String)
    case invalidJSON
    case invalidIdentifiers

    public var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "Cannot read calendar configuration: \(reason)"
        case .invalidJSON: return "config.json must contain a JSON object."
        case .invalidIdentifiers:
            return "calendarIdentifiers must be an array of non-empty strings (an empty array selects no calendars)."
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
}

public struct AvailableCalendar: Equatable {
    public let identifier: String
    public let title: String

    public init(identifier: String, title: String) {
        self.identifier = identifier
        self.title = title
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
