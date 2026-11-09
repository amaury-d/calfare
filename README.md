# Calflare

Calflare is a local macOS meeting reminder. It checks calendars exposed to
Apple's Calendar framework (EventKit) and shows a full-screen animated alert
about a minute before an event. It does not connect to Outlook or Microsoft
Graph; an Outlook account is usable only when its calendars are enabled and
visible to macOS Calendar.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools with Swift 5.9 or later
- Calendar accounts already configured in macOS, with Calendar access enabled

## Build and install from source

```sh
./build.sh
./install.sh
```

`build.sh` builds and ad-hoc signs a self-contained `Calflare.app` in
`build/`; it does not read calendars, request permission, show a window, or
load a service. Pass `--output "/path/with spaces & symbols/Calflare.app"` to
choose another build destination. The built app keeps its overlay executable
and English/French resources together, so it can be moved independently of
the checkout.

`install.sh` builds the app and installs it at `~/Applications/Calflare.app`,
then loads a per-user LaunchAgent that checks every 20 seconds. On first use,
allow Calflare to access Calendars in System Settings > Privacy & Security >
Calendars. Renaming the app requires consent again. Ad-hoc signing is intended
for local source builds and does not guarantee that macOS will retain
permission after a rebuild.

### Migrating the legacy Outlook Meeting Alert

The installer detects the old `com.local.outlook-meeting-alert` service and
refuses to replace it unless migration is explicit:

```sh
./install.sh --migrate
```

Migration builds and validates Calflare before stopping the old service,
copies its seven-day deduplication state if Calflare has no state yet, and
removes the old LaunchAgent only after the new service loads successfully.
The old checkout and its `build/` artifacts are not removed. If service
loading fails, the installer attempts to restore the previous service; check
the terminal output and, if necessary, restore the legacy plist from
`~/Library/LaunchAgents/com.local.outlook-meeting-alert.plist` and load it with
`launchctl bootstrap gui/$(id -u) <plist-path>`. Calendar consent may need to
be granted again.

## Preview and calendar selection

```sh
"$HOME/Applications/Calflare.app/Contents/MacOS/CalflareAgent" --test
"$HOME/Applications/Calflare.app/Contents/MacOS/CalflareAgent" --list-calendars
"$HOME/Applications/Calflare.app/Contents/MacOS/CalflareAgent" --list
```

`--test` uses synthetic event data and does not request Calendar access.
`--list-calendars` prints each calendar's identifier, title, and source, and
is independent of the selection filter. `--list` shows the next seven days
from the same selected calendars used for alerts. Calendar identifiers are
local to this macOS calendar store and are not portable account identifiers.

By default, alerts use all calendars macOS makes available. To select specific
calendars, create
`~/Library/Application Support/Calflare/config.json`:

```json
{
  "calendarIdentifiers": [
    "identifier-copied-from-list-calendars"
  ]
}
```

Only exact identifiers are matched; duplicate calendar names are fine.
Unavailable configured identifiers are reported and never cause a fallback to
all calendars. Use an empty array (`"calendarIdentifiers": []`) to disable
alerts for every calendar. An absent configuration file or absent key selects
all calendars. Invalid JSON or values stop processing with an actionable
error rather than broadening access.

## Behavior and limitations

- Checks every 20 seconds and alerts for eligible timed events 45–85 seconds
  away. This is an approximate one-minute warning, not a precise alarm.
- Skips all-day, cancelled, and declined events, including titles prefixed
  with common English or French cancellation/decline markers.
- Displays the title and location on each display. `Return` joins only when a
  Teams link was detected; `Escape` closes the alert. Other meeting providers
  are not detected. Alerts dismiss automatically after 15 minutes.
- Stores occurrence-based deduplication keys for seven days in
  `~/Library/Application Support/Calflare/alerted-events.txt`.
- A sleeping Mac may miss an event: Calflare does not wake the computer.

## Privacy and troubleshooting

Calflare has no telemetry and makes no Graph API requests. Event details are
read locally through EventKit. Calendar identifiers and deduplication state
are stored locally. The meeting destination is opened only when the user
activates the Teams button in an alert.

If calendars are missing, confirm the account exposes calendars to macOS
Calendar and that Calflare has Calendar permission. The account need not be
Exchange specifically. Check the LaunchAgent output at
`~/Library/Logs/Calflare/`; use `--list-calendars` to see the calendars
EventKit exposes. If a configured calendar identifier is unavailable, list
calendars again and update `config.json`.

## Uninstallation

```sh
./uninstall.sh
```

This stops and removes only Calflare's LaunchAgent and installed app.
Configuration, deduplication state, and logs remain in your home directory.
To remove those data files as well, do so explicitly after uninstalling:

```sh
rm -rf "$HOME/Library/Application Support/Calflare"
rm -rf "$HOME/Library/Logs/Calflare"
```

The legacy Outlook Meeting Alert service, if present, is not removed by
Calflare's uninstaller.

## Development and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and packaging checks.
Calflare is available under the [MIT license](LICENSE).
