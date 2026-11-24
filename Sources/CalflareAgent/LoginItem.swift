import AppKit
import ServiceManagement

/// Starting Calflare at login.
///
/// `make install` already does this with a LaunchAgent, so this type defers to it rather than
/// competing: it never writes or deletes a file it did not create. The login item therefore
/// matters for an app that was downloaded and dragged into place.
enum LoginItem {
    enum Blocker: Equatable {
        /// Registering from a translocated or removable location records a path that will not
        /// exist at the next login, and `register()` does not complain about it.
        case volatileLocation
        case signatureRejected
        case failed(String)
    }

    enum State: Equatable {
        case managedByLaunchAgent(enabled: Bool)
        case enabled
        case requiresApproval
        case disabled
        case unavailable(Blocker)
    }

    private static let label = "com.calflare.agent"

    /// Stable, machine-readable names for the one-shot CLI flags.
    static func name(of state: State) -> String {
        switch state {
        case .managedByLaunchAgent(let enabled):
            return enabled ? "managed-by-launch-agent" : "managed-by-launch-agent-disabled"
        case .enabled: return "enabled"
        case .requiresApproval: return "requires-approval"
        case .disabled: return "disabled"
        case .unavailable(.volatileLocation): return "unavailable-volatile-location"
        case .unavailable(.signatureRejected): return "unavailable-signature-rejected"
        case .unavailable(.failed): return "unavailable-failed"
        }
    }

    private static let versionURL =
        AgentPaths.dataDirectory.appendingPathComponent("login-item-version.txt")

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// Describes what happens at the next login, not how this process started. True when the
    /// LaunchAgent plist exists and carries our label — the same safety check the Makefile
    /// makes with `plutil -extract Label`.
    static var isManagedByLaunchAgent: Bool {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any]
        else { return false }
        return plist["Label"] as? String == label
    }

    /// macOS records the bundle's location, so a path that disappears must be refused instead
    /// of registered silently.
    private static var isInVolatileLocation: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        if path.contains("/AppTranslocation/") { return true }
        if path.hasPrefix("/Volumes/") || path.hasPrefix("/private/var/folders/") { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix("\(home)/Downloads/") || path.hasPrefix("\(home)/.Trash/")
    }

    /// Never cache the result: the user can flip these switches in System Settings at any time.
    static func state() -> State {
        if isManagedByLaunchAgent {
            // Tells us whether the user switched the LaunchAgent off in Login Items.
            let legacy = SMAppService.statusForLegacyPlist(at: launchAgentURL)
            return .managedByLaunchAgent(enabled: legacy != .requiresApproval)
        }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound:
            return isInVolatileLocation ? .unavailable(.volatileLocation) : .disabled
        @unknown default: return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard !isManagedByLaunchAgent else { return }
        if enabled {
            guard !isInVolatileLocation else { throw Error.volatileLocation }
            do {
                try SMAppService.mainApp.register()
            } catch let error as NSError where error.code == kSMErrorAlreadyRegistered {
                // Already in the requested state.
            }
            try? Data(currentVersion.utf8).write(to: versionURL, options: .atomic)
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch let error as NSError where error.code == kSMErrorJobNotFound {
                // Already in the requested state.
            }
            try? FileManager.default.removeItem(at: versionURL)
        }
    }

    /// An ad-hoc signature's designated requirement is a hash of the binary, so the app's code
    /// identity changes with every build. A registration made by an earlier build can go stale
    /// and stop launching; re-register once when the version moved.
    static func refreshRegistrationIfNeeded() {
        guard !isManagedByLaunchAgent, SMAppService.mainApp.status == .enabled else { return }
        let registered = try? String(contentsOf: versionURL, encoding: .utf8)
        guard registered?.trimmingCharacters(in: .whitespacesAndNewlines) != currentVersion else {
            return
        }
        do {
            try SMAppService.mainApp.unregister()
            try SMAppService.mainApp.register()
            try? Data(currentVersion.utf8).write(to: versionURL, options: .atomic)
        } catch {
            log("Cannot refresh the login item after an update: \(error.localizedDescription)")
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    enum Error: Swift.Error, LocalizedError {
        case volatileLocation

        var errorDescription: String? {
            NSLocalizedString("startup.volatileLocation", comment: "")
        }
    }
}
