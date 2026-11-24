import Foundation

/// One-shot, non-graphical invocations. Never touches NSApplication or the status item, and
/// keeps the standard-output strings the README and Makefile rely on.
enum AgentCLI {
    static func run(_ arguments: [String]) -> Never {
        if arguments.contains("--test") {
            do {
                try OverlayLauncher.launchPreview()
                print("test-alert=1")
                exit(0)
            } catch {
                log("Cannot start \(AgentPaths.overlayBinary): \(error)")
                exit(1)
            }
        }

        let runtime = AgentRuntime()
        let listing = arguments.contains("--list-calendars") || arguments.contains("--list")
        guard CalendarAccess.requestBlocking(runtime.store) else {
            log("Calendar access is unavailable. Grant Calflare access in System Settings > Privacy & Security > Calendars.")
            exit(listing ? 1 : 0)
        }

        if arguments.contains("--list-calendars") {
            runtime.listCalendars()
            exit(0)
        }

        if arguments.contains("--list") {
            do {
                let resolved = try runtime.resolve()
                guard !resolved.calendars.isEmpty else {
                    print("eventkit-selected-calendars=0")
                    exit(0)
                }
                runtime.listEvents(calendars: resolved.calendars)
                exit(0)
            } catch {
                log(error.localizedDescription)
                exit(1)
            }
        }

        // --once
        do {
            switch try runtime.tick() {
            case .noCalendars: print("eventkit-selected-calendars=0")
            case .alerted(let count): print("eventkit-alerts=\(count)")
            }
            exit(0)
        } catch {
            log(error.localizedDescription)
            exit(1)
        }
    }
}
