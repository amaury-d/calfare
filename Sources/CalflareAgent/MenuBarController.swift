import AppKit
import EventKit

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    // NSApplication holds its delegate weakly.
    private static var instance: MenuBarController?
    private static var lockDescriptor: Int32 = -1

    private let runtime = AgentRuntime()
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var windowController: CalendarsWindowController?

    static func runResident() {
        guard acquireSingleInstanceLock() else {
            log("Calflare is already running.")
            exit(0)  // status 0 so KeepAlive(SuccessfulExit=false) does not relaunch
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = MenuBarController()
        instance = controller
        app.delegate = controller
        app.run()
    }

    /// Prevents a second status item when the app is double-clicked while launchd runs it, or
    /// when an old StartInterval LaunchAgent is still loaded.
    private static func acquireSingleInstanceLock() -> Bool {
        try? FileManager.default.createDirectory(
            at: AgentPaths.dataDirectory, withIntermediateDirectories: true
        )
        let descriptor = open(AgentPaths.lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            log("Cannot open \(AgentPaths.lockURL.path); continuing without an instance lock.")
            return true
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }
        lockDescriptor = descriptor  // held for the life of the process
        return true
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        // The status item exists first so the menu is reachable while permission is pending.
        if CalendarAccess.state() == .notDetermined {
            CalendarAccess.request(runtime.store) { [weak self] _ in
                Task { @MainActor in self?.performTick() }
            }
        }

        let timer = Timer.scheduledTimer(
            timeInterval: 20, target: self, selector: #selector(timerFired),
            userInfo: nil, repeats: true
        )
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        performTick()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage()
        item.button?.toolTip = "Calflare"

        let menu = NSMenu()
        menu.addItem(withTitle: NSLocalizedString("menu.calendars", comment: ""),
                     action: #selector(openCalendars), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("menu.testAlert", comment: ""),
                     action: #selector(testAlert), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("menu.quit", comment: ""),
                     action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    private static func statusImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        let fallback = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Calflare")
        fallback?.isTemplate = true
        return fallback
    }

    @objc private func openCalendars() {
        if windowController == nil {
            windowController = CalendarsWindowController(runtime: runtime)
        }
        windowController?.show()
    }

    @objc private func testAlert() {
        do {
            try OverlayLauncher.launchPreview()
        } catch {
            log("Cannot start \(AgentPaths.overlayBinary): \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)  // exit status 0: launchd does not relaunch
    }

    // MARK: - Ticking

    @objc private func timerFired() {
        performTick()
    }

    @objc private func didWake() {
        performTick()
    }

    private func performTick() {
        guard CalendarAccess.state() == .granted else { return }
        do {
            if case .alerted(let count) = try runtime.tick(), count > 0 {
                // Only log when something happened, or stdout.log grows forever.
                print("eventkit-alerts=\(count)")
                fflush(stdout)
            }
        } catch {
            // Never exit: a configuration error must skip alerts, not restart in a loop.
            log(error.localizedDescription)
        }
    }
}
