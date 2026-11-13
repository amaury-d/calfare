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

## Preview an alert

```sh
make preview
"$HOME/Applications/Calflare.app/Contents/MacOS/CalflareAgent" --test
```

`--test` uses synthetic event data and does not request Calendar access.

## Choose which calendars trigger alerts

By default, Calflare uses all calendars macOS makes available. To limit alerts
to specific calendars:

1. **List your calendars.** In a terminal, run:

   ```sh
   calflare="$HOME/Applications/Calflare.app/Contents/MacOS/CalflareAgent"
   "$calflare" --list-calendars
   ```

   If you installed with a custom `INSTALL_DIR`, replace
   `$HOME/Applications` with that directory. The `calflare` variable lasts
   only for the current terminal session; set it again in a new session.

   macOS may ask you to grant Calendar access to your **terminal app**, rather
   than Calflare, for these commands. If access was denied, enable it for your
   terminal app under System Settings > Privacy & Security > Calendars. The
   background agent needs Calendar access for Calflare separately. The CLI
   error message says “Grant Calflare access” even if the terminal needs access.

2. **Find the identifier.** The output lists every available calendar, even
   if a filter is already configured. For example:

   ```text
   11111111-1111-4111-8111-111111111111 | Work | Example Exchange
   22222222-2222-4222-8222-222222222222 | Work | Example Google
   ```

   Copy the identifier in the first column for each calendar you want. The
   final column identifies the account, which helps distinguish calendars
   with the same name. To find a calendar by name, you can filter the output:

   ```sh
   "$calflare" --list-calendars | grep -i work
   ```

3. **Create the configuration file.** The following example overwrites any
   existing `config.json`. Back it up first if you need to keep its contents.

   ```sh
   mkdir -p "$HOME/Library/Application Support/Calflare"
   cat > "$HOME/Library/Application Support/Calflare/config.json" <<'JSON'
   {
     "calendarIdentifiers": [
       "11111111-1111-4111-8111-111111111111"
     ]
   }
   JSON
   ```

   Open the file in TextEdit:

   ```sh
   open -e "$HOME/Library/Application Support/Calflare/config.json"
   ```

   Replace the example identifier with the one you copied and save the file.
   The example alone will not select a real calendar. For multiple calendars,
   add their identifiers as quoted strings separated by commas. Identifiers
   must match exactly and are local to your macOS calendar store. If an account
   is removed and added again, list the calendars and update the identifiers
   if needed.

4. **Check the selection.**

   ```sh
   "$calflare" --list
   ```

   This shows timed events in the next seven days from the selected calendars.
   Each line ends with `Calendar [Account]`. It may include events that the
   alert rules skip, such as declined events. If no calendars are selected,
   it prints `eventkit-selected-calendars=0` instead. The background agent
   reads the configuration on its next check, normally within 20 seconds; no
   restart is needed.

To select all calendars again, remove `config.json` or remove the
`calendarIdentifiers` key. To disable alerts for all calendars, set
`"calendarIdentifiers": []`. An unavailable identifier never causes a
fallback to all calendars, and invalid JSON or values stop processing rather
than broadening the selection. Check `~/Library/Logs/Calflare/stderr.log`
or run `make logs` for errors.

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
Exchange specifically. If listing calendars in a terminal fails, check that
the terminal app also has Calendar access. See
[calendar selection](#choose-which-calendars-trigger-alerts) to list
calendars and update unavailable identifiers. Run `make logs` to follow the
LaunchAgent output, or inspect the files in `~/Library/Logs/Calflare/`.
These files grow over time; they may be removed when no longer needed.

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
