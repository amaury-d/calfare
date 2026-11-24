import CalflareCore
import EventKit
import Foundation

enum TickOutcome: Equatable {
    case noCalendars
    case alerted(Int)
}

enum AgentRuntimeError: Error, LocalizedError {
    case configuration(Error)
    case state(Error)
    case alert(Error)

    var errorDescription: String? {
        switch self {
        case .configuration(let error):
            return "\(error.localizedDescription) Fix \(AgentPaths.configURL.path); refusing to broaden calendar selection."
        case .state(let error):
            return "Cannot read deduplication state at \(AgentPaths.stateURL.path): \(error)"
        case .alert(let error):
            return "Cannot persist or launch alert for event: \(error)"
        }
    }
}

struct ResolvedCalendars {
    let selection: CalendarSelection
    let calendars: [EKCalendar]
    let unavailable: Set<String>
}

final class AgentRuntime {
    let store: EKEventStore
    private var loggedUnavailable: Set<String> = []

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func availableCalendars() -> [AvailableCalendar] {
        store.calendars(for: .event).map {
            AvailableCalendar(
                identifier: $0.calendarIdentifier,
                title: $0.title,
                sourceTitle: $0.source?.title ?? ""
            )
        }
    }

    /// The only producer of the calendar list handed to EventKit predicates. A configuration
    /// error throws instead of falling back to "all calendars".
    func resolve() throws -> ResolvedCalendars {
        let selection: CalendarSelection
        do {
            selection = try CalendarConfiguration.load(from: AgentPaths.configURL)
        } catch {
            throw AgentRuntimeError.configuration(error)
        }
        let all = store.calendars(for: .event)
        let values = all.map {
            AvailableCalendar(
                identifier: $0.calendarIdentifier,
                title: $0.title,
                sourceTitle: $0.source?.title ?? ""
            )
        }
        let result = selectCalendars(values, using: selection)
        // Log each change once: the resident app resolves every 20 seconds.
        if result.unavailableIdentifiers != loggedUnavailable {
            for identifier in result.unavailableIdentifiers.sorted() {
                log("Calendar identifier is not available in this calendar store: \(identifier)")
            }
            loggedUnavailable = result.unavailableIdentifiers
        }
        let selectedIdentifiers = Set(result.selected.map(\.identifier))
        return ResolvedCalendars(
            selection: selection,
            calendars: all.filter { selectedIdentifiers.contains($0.calendarIdentifier) },
            unavailable: result.unavailableIdentifiers
        )
    }

    func listCalendars() {
        for calendar in store.calendars(for: .event) {
            print("\(calendar.calendarIdentifier) | \(calendar.title) | \(calendar.source?.title ?? "")")
        }
    }

    func listEvents(calendars: [EKCalendar]) {
        // EventKit can interpret an empty calendar list as an unrestricted query.
        guard !calendars.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        let predicate = store.predicateForEvents(
            withStart: Date(), end: Date().addingTimeInterval(7 * 86_400), calendars: calendars
        )
        for event in store.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate })
        where !event.isAllDay {
            print("\(formatter.string(from: event.startDate)) | \(event.title ?? "") | \(event.calendar.title) [\(event.calendar.source?.title ?? "")]")
        }
    }

    @discardableResult
    func tick(now: Date = Date()) throws -> TickOutcome {
        // A resident process can otherwise keep serving stale data.
        store.refreshSourcesIfNecessary()
        let resolved = try resolve()
        // EventKit can interpret an empty calendar list as an unrestricted query.
        guard !resolved.calendars.isEmpty else { return .noCalendars }

        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(45), end: now.addingTimeInterval(85),
            calendars: resolved.calendars
        )
        var keys: [String]
        do {
            keys = try readState()
        } catch {
            throw AgentRuntimeError.state(error)
        }

        var alerts = 0
        for event in store.events(matching: predicate) {
            let record = CalendarEvent(
                start: event.startDate,
                isAllDay: event.isAllDay,
                isCancelled: event.status == .canceled,
                isDeclined: event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined,
                title: event.title ?? ""
            )
            guard EventEligibility.shouldAlert(record, now: now) else { continue }
            let key = EventDeduplication.key(
                start: event.startDate,
                identifier: event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? ""
            )
            guard !keys.contains(key) else { continue }
            let source = [event.location, event.notes, event.url?.absoluteString]
                .compactMap { $0 }.joined(separator: "\n")
            let sourceURL = TeamsLink.extract(from: source) ?? ""
            keys.append(key)
            do {
                // Persist before launching so a crash cannot produce a second alert.
                try writeState(keys)
                try OverlayLauncher.launch(
                    title: event.title ?? "",
                    details: event.location ?? "",
                    url: sourceURL,
                    start: String(Int(event.startDate.timeIntervalSince1970))
                )
                alerts += 1
            } catch {
                keys.removeAll { $0 == key }
                do {
                    try writeState(keys)
                } catch {
                    log("Cannot restore deduplication state after launch failure: \(error)")
                }
                throw AgentRuntimeError.alert(error)
            }
        }
        return .alerted(alerts)
    }

    private func readState() throws -> [String] {
        guard FileManager.default.fileExists(atPath: AgentPaths.stateURL.path) else { return [] }
        return EventDeduplication.retainedKeys(
            try String(contentsOf: AgentPaths.stateURL, encoding: .utf8)
                .split(separator: "\n").map(String.init),
            now: Date()
        )
    }

    private func writeState(_ keys: [String]) throws {
        try FileManager.default.createDirectory(
            at: AgentPaths.dataDirectory, withIntermediateDirectories: true
        )
        try (keys.joined(separator: "\n") + "\n")
            .write(to: AgentPaths.stateURL, atomically: true, encoding: .utf8)
    }
}
