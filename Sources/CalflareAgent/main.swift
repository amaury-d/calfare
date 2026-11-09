import CalflareCore
import EventKit
import Foundation

let appContents = Bundle.main.bundleURL.appendingPathComponent("Contents")
let overlayBinary = appContents.appendingPathComponent("MacOS/CalflareOverlay").path
let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Calflare")
let configURL = dataDirectory.appendingPathComponent("config.json")
let stateURL = dataDirectory.appendingPathComponent("alerted-events.txt")
let arguments = Array(CommandLine.arguments.dropFirst())

func log(_ message: String) {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
}

func requestCalendarAccess(_ store: EKEventStore) -> Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if status == .fullAccess { return true }
    guard status == .notDetermined else { return false }
    let semaphore = DispatchSemaphore(value: 0)
    var granted = false
    store.requestFullAccessToEvents { ok, _ in
        granted = ok
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 120) == .success else { return false }
    return granted
}

func loadSelection() throws -> CalendarSelection {
    try CalendarConfiguration.load(from: configURL)
}

func calendarSelection(_ calendars: [EKCalendar], selection: CalendarSelection) -> [EKCalendar] {
    let values = calendars.map { AvailableCalendar(identifier: $0.calendarIdentifier, title: $0.title) }
    let result = selectCalendars(values, using: selection)
    for identifier in result.unavailableIdentifiers.sorted() {
        log("Calendar identifier is not available in this calendar store: \(identifier)")
    }
    let selectedIdentifiers = Set(result.selected.map(\.identifier))
    return calendars.filter { selectedIdentifiers.contains($0.calendarIdentifier) }
}

func launchOverlay(title: String, details: String, url: String, start: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: overlayBinary)
    process.arguments = ["--title", title, "--details", details, "--url", url, "--start", start]
    try process.run()
}

func readState() throws -> [String] {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return [] }
    return EventDeduplication.retainedKeys(
        try String(contentsOf: stateURL, encoding: .utf8).split(separator: "\n").map(String.init),
        now: Date()
    )
}

func writeState(_ keys: [String]) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    try (keys.joined(separator: "\n") + "\n").write(to: stateURL, atomically: true, encoding: .utf8)
}

func listCalendars(_ store: EKEventStore) {
    for calendar in store.calendars(for: .event) {
        print("\(calendar.calendarIdentifier) | \(calendar.title) | \(calendar.source.title)")
    }
}

func listEvents(_ store: EKEventStore, calendars: [EKCalendar]) {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale.current
    let predicate = store.predicateForEvents(
        withStart: Date(), end: Date().addingTimeInterval(7 * 86_400), calendars: calendars
    )
    for event in store.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate })
    where !event.isAllDay {
        print("\(formatter.string(from: event.startDate)) | \(event.title ?? "") | \(event.calendar.title) [\(event.calendar.source.title)]")
    }
}

func runPreview() -> Never {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: overlayBinary)
    process.arguments = ["--preview"]
    do {
        try process.run()
        print("test-alert=1")
        exit(0)
    } catch {
        log("Cannot start \(overlayBinary): \(error)")
        exit(1)
    }
}

if arguments.contains("--test") {
    runPreview()
}

let store = EKEventStore()
guard requestCalendarAccess(store) else {
    log("Calendar access is unavailable. Grant Calflare access in System Settings > Privacy & Security > Calendars.")
    exit(arguments.contains("--list-calendars") || arguments.contains("--list") ? 1 : 0)
}

if arguments.contains("--list-calendars") {
    listCalendars(store)
    exit(0)
}

let selection: CalendarSelection
do {
    selection = try loadSelection()
} catch {
    log("\(error.localizedDescription) Fix \(configURL.path); refusing to broaden calendar selection.")
    exit(1)
}

let allCalendars = store.calendars(for: .event)
let calendars = calendarSelection(allCalendars, selection: selection)
// EventKit can interpret an empty calendar list as an unrestricted query.
guard !calendars.isEmpty else {
    print("eventkit-selected-calendars=0")
    exit(0)
}

if arguments.contains("--list") {
    listEvents(store, calendars: calendars)
    exit(0)
}

let now = Date()
let predicate = store.predicateForEvents(
    withStart: now.addingTimeInterval(45), end: now.addingTimeInterval(85), calendars: calendars
)
var keys: [String]
do {
    keys = try readState()
} catch {
    log("Cannot read deduplication state at \(stateURL.path): \(error)")
    exit(1)
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
        try writeState(keys)
        try launchOverlay(
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
        log("Cannot persist or launch alert for event: \(error)")
        exit(1)
    }
}
print("eventkit-alerts=\(alerts)")
