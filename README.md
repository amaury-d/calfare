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
make install
```

Use `make` or `make app` to build and ad-hoc sign a self-contained
`build/Calflare.app` without accessing calendars, showing a window, or loading
a service. The app includes its overlay executable and English/French
resources, so it can be moved independently of the checkout.

`make install` builds the app, installs it at `~/Applications/Calflare.app`,
and loads a per-user LaunchAgent that checks every 20 seconds. To choose a
different application directory, use `make install INSTALL_DIR="/path/to/apps"`;
use the same directory for uninstallation. On first use, allow Calflare to
access Calendars in System Settings > Privacy & Security > Calendars. Ad-hoc
signing is intended for local source builds and does not guarantee that macOS
will retain permission after a rebuild.

## Preview and calendar selection

```sh
make preview
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
Exchange specifically. Run `make logs` to follow the LaunchAgent output, or
inspect the files in `~/Library/Logs/Calflare/`. These files grow over time;
they may be removed when no longer needed. Use `--list-calendars` to see the
calendars EventKit exposes. If a configured calendar identifier is
unavailable, list calendars again and update `config.json`.

## Uninstallation

```sh
make uninstall
```

This stops and removes only Calflare's LaunchAgent and installed app.
Configuration, deduplication state, and logs remain in your home directory.
To remove those data files as well, do so explicitly after uninstalling:

```sh
rm -rf "$HOME/Library/Application Support/Calflare"
rm -rf "$HOME/Library/Logs/Calflare"
```

## Development and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and packaging checks.
Calflare is available under the [MIT license](LICENSE).
