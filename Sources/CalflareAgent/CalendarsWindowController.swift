import AppKit
import EventKit
import SwiftUI

@MainActor
final class CalendarsWindowController: NSObject, NSWindowDelegate {
    private let model: CalendarsModel
    private var window: NSWindow?

    init(runtime: AgentRuntime) {
        model = CalendarsModel(runtime: runtime)
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(refreshIfVisible),
                           name: .EKEventStoreChanged, object: runtime.store)
        center.addObserver(self, selector: #selector(refreshIfVisible),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func show() {
        model.reload()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = NSLocalizedString("window.calendars.title", comment: "")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: CalendarsView(model: model, close: { [weak window] in window?.close() })
            )
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        // An accessory app is never frontmost on its own.
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshIfVisible() {
        if window?.isVisible == true { model.reload() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }
}
