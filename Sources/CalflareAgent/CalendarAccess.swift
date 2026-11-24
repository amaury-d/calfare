import AppKit
import EventKit

enum CalendarAccess {
    enum State: Equatable {
        case granted
        case notDetermined
        case denied
    }

    static func state() -> State {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Blocks the calling thread. For the one-shot CLI only: there is no run loop to starve.
    static func requestBlocking(_ store: EKEventStore) -> Bool {
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

    /// Non-blocking request for the resident app; `completion` runs on the main queue.
    static func request(_ store: EKEventStore, completion: @escaping @Sendable (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
