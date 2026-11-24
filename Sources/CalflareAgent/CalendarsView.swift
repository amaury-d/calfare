import CalflareCore
import SwiftUI

@MainActor
final class CalendarsModel: ObservableObject {
    @Published private(set) var access: CalendarAccess.State = .notDetermined
    @Published private(set) var groups: [CalendarGroup] = []
    @Published private(set) var selection: CalendarSelection = .all
    @Published private(set) var unavailable: Set<String> = []
    @Published private(set) var configurationError: String?
    @Published private(set) var saveError: String?

    private let runtime: AgentRuntime
    private var available: [AvailableCalendar] = []

    init(runtime: AgentRuntime) {
        self.runtime = runtime
    }

    var configurationIsValid: Bool { configurationError == nil }

    /// config.json is the single source of truth: every refresh re-reads it.
    func reload() {
        access = CalendarAccess.state()
        guard access == .granted else {
            groups = []
            available = []
            return
        }
        runtime.store.refreshSourcesIfNecessary()
        available = runtime.availableCalendars()
        groups = groupCalendarsBySource(available)
        do {
            selection = try CalendarConfiguration.load(from: AgentPaths.configURL)
            configurationError = nil
            unavailable = selectCalendars(available, using: selection).unavailableIdentifiers
        } catch {
            configurationError = "\(error.localizedDescription) (\(AgentPaths.configURL.path))"
            unavailable = []
        }
    }

    func isSelected(_ identifier: String) -> Bool {
        CalendarToggle.isSelected(identifier, in: selection)
    }

    func set(_ isOn: Bool, for identifier: String) {
        apply(CalendarToggle.setting(isOn, for: identifier, in: selection, available: available),
              retaining: unavailable)
    }

    func setAll(_ isOn: Bool) {
        // Turning "all" off is an explicit "nothing", so nothing is retained either.
        apply(CalendarToggle.settingAll(isOn, available: available), retaining: [])
    }

    func requestAccess() {
        CalendarAccess.request(runtime.store) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func apply(_ newSelection: CalendarSelection, retaining retained: Set<String>) {
        saveError = nil
        do {
            try CalendarConfiguration.save(
                newSelection, to: AgentPaths.configURL, retainingUnavailable: retained
            )
        } catch {
            saveError = String(
                format: NSLocalizedString("error.saveFailed", comment: ""),
                error.localizedDescription
            )
        }
        // Re-read even after a failure so the UI shows what is actually on disk.
        reload()
    }
}

struct CalendarsView: View {
    @ObservedObject var model: CalendarsModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.access == .granted {
                calendars
            } else {
                accessPrompt
            }
            HStack {
                Spacer()
                Button(NSLocalizedString("button.close", comment: ""), action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 460)
    }

    private var allBinding: Binding<Bool> {
        Binding(
            get: { CalendarToggle.isAllSelected(model.selection) },
            set: { model.setAll($0) }
        )
    }

    private var calendars: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(NSLocalizedString("calendars.all", comment: ""), isOn: allBinding)
                    .fontWeight(.semibold)
                Text(NSLocalizedString("calendars.allHint", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
            Divider()
            if model.groups.isEmpty {
                Text(NSLocalizedString("calendars.empty", comment: ""))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(model.groups, id: \.sourceTitle) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                if !group.sourceTitle.isEmpty {
                                    Text(group.sourceTitle)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(group.calendars, id: \.identifier) { calendar in
                                    Toggle(calendar.title, isOn: binding(for: calendar.identifier))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(!model.configurationIsValid)
            }
            caption
        }
    }

    private func binding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { model.isSelected(identifier) },
            set: { model.set($0, for: identifier) }
        )
    }

    @ViewBuilder
    private var caption: some View {
        if let message = model.configurationError ?? model.saveError {
            Text(message).font(.caption).foregroundStyle(.red)
        } else if model.selection == .identifiers([]) {
            Text(NSLocalizedString("calendars.none", comment: ""))
                .font(.caption).foregroundStyle(.orange)
        } else if !model.unavailable.isEmpty {
            Text(NSLocalizedString("calendars.unavailable", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var accessPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("access.denied", comment: "")).font(.headline)
            Text(NSLocalizedString("access.deniedDetail", comment: ""))
                .foregroundStyle(.secondary)
            if model.access == .notDetermined {
                Button(NSLocalizedString("access.request", comment: ""), action: model.requestAccess)
            } else {
                Button(NSLocalizedString("access.openSettings", comment: ""),
                       action: CalendarAccess.openPrivacySettings)
            }
            Spacer(minLength: 0)
        }
    }
}
