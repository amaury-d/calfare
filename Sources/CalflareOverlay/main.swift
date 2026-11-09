import AppKit
import Combine
import SwiftUI

struct AlertOptions {
    var title = NSLocalizedString("meeting.fallbackTitle", bundle: .module, comment: "")
    var details = ""
    var joinURL: URL?
    var start: Date?
    var autoCloseSeconds: TimeInterval = 900

    static func parse(_ arguments: [String]) -> AlertOptions {
        var options = AlertOptions()
        if arguments.contains("--preview") {
            options.title = NSLocalizedString("preview.title", bundle: .module, comment: "")
            options.details = NSLocalizedString("preview.details", bundle: .module, comment: "")
            options.joinURL = URL(string: "https://teams.microsoft.com/")
            options.start = Date().addingTimeInterval(60)
            return options
        }
        var index = 1
        while index < arguments.count - 1 {
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--title":
                if !value.isEmpty { options.title = value }
            case "--details": options.details = value
            case "--url": options.joinURL = value.isEmpty ? nil : URL(string: value)
            case "--start": options.start = TimeInterval(value).map(Date.init(timeIntervalSince1970:))
            case "--auto-close": options.autoCloseSeconds = TimeInterval(value) ?? options.autoCloseSeconds
            default: index -= 1
            }
            index += 2
        }
        return options
    }
}

struct PillButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 22, weight: .bold))
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? Color(red: 0.36, green: 0.12, blue: 0.62) : .white)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.18)))
            .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: prominent ? 0 : 2))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct AlertView: View {
    let options: AlertOptions
    let close: () -> Void

    @State private var pulse = false
    @State private var appeared = false
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var countdown: String {
        guard let start = options.start else {
            return NSLocalizedString("countdown.starts", bundle: .module, comment: "")
        }
        let seconds = Int(start.timeIntervalSince(now).rounded())
        if seconds <= 0 {
            return NSLocalizedString("countdown.now", bundle: .module, comment: "")
        }
        let format = NSLocalizedString("countdown.in", bundle: .module, comment: "")
        return String(format: format, locale: Locale.current, seconds / 60, seconds % 60)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.05, blue: 0.55), Color(red: 0.95, green: 0.38, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .hueRotation(.degrees(pulse ? 35 : -10))
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: pulse)
            .opacity(0.94)
            .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    ForEach(0..<3, id: \.self) { ring in
                        Circle()
                            .stroke(Color.white.opacity(0.7), lineWidth: 4)
                            .frame(width: 150, height: 150)
                            .scaleEffect(pulse ? 2.3 : 1)
                            .opacity(pulse ? 0 : 0.9)
                            .animation(
                                .easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(ring) * 0.65),
                                value: pulse
                            )
                    }
                    Image(systemName: options.joinURL == nil ? "calendar" : "video.fill")
                        .font(.system(size: 68, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(pulse ? 1.12 : 0.94)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
                }
                .frame(height: 340)

                Text(countdown)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()

                Text(options.title)
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 80)

                if !options.details.isEmpty {
                    Text(options.details)
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 140)
                }

                HStack(spacing: 22) {
                    if let url = options.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                            close()
                        } label: {
                            Label(
                                NSLocalizedString("button.joinTeams", bundle: .module, comment: ""),
                                systemImage: "video.fill"
                            )
                        }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                    }
                    Button(
                        NSLocalizedString("button.close", bundle: .module, comment: ""),
                        action: close
                    )
                        .buttonStyle(PillButtonStyle(prominent: options.joinURL == nil))
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 12)
            }
            .scaleEffect(appeared ? 1 : 0.75)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            pulse = true
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { appeared = true }
        }
        .onReceive(clock) { now = $0 }
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
struct MeetingAlert {
    @MainActor static var windows: [NSWindow] = []

    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            for key in [
                "meeting.fallbackTitle", "countdown.in", "button.joinTeams",
                "button.close", "preview.title", "preview.details"
            ] {
                print(Bundle.module.localizedString(forKey: key, value: nil, table: nil))
            }
            return
        }
        let options = AlertOptions.parse(CommandLine.arguments)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let close: () -> Void = { NSApp.terminate(nil) }

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.contentView = NSHostingView(rootView: AlertView(options: options, close: close))
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        windows.first?.makeKey()
        app.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + options.autoCloseSeconds) { close() }
        app.run()
    }
}
