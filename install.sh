#!/bin/zsh

set -euo pipefail

readonly project_dir="${0:A:h}"
readonly applications_dir="$HOME/Applications"
readonly app_path="$applications_dir/Calflare.app"
readonly candidate="$applications_dir/.Calflare-candidate.app"
readonly launch_agents_dir="$HOME/Library/LaunchAgents"
readonly logs_dir="$HOME/Library/Logs/Calflare"
readonly plist_path="$launch_agents_dir/com.calflare.agent.plist"
readonly pending_plist="$launch_agents_dir/.com.calflare.agent.plist.new.$$"
readonly previous_plist="$launch_agents_dir/.com.calflare.agent.plist.previous"
readonly previous_app="$applications_dir/.Calflare.previous.app"
readonly service_name="gui/$(id -u)/com.calflare.agent"
readonly legacy_plist="$launch_agents_dir/com.local.outlook-meeting-alert.plist"
readonly legacy_service="gui/$(id -u)/com.local.outlook-meeting-alert"
readonly legacy_state="$HOME/Library/Application Support/OutlookMeetingAlert/alerted-eventkit.txt"
readonly data_dir="$HOME/Library/Application Support/Calflare"

migrate=false
while (( $# )); do
  case "$1" in
    --migrate) migrate=true; shift ;;
    *) print -u2 "Unknown argument: $1"; exit 2 ;;
  esac
done

service_loaded() {
  /bin/launchctl print "$1" >/dev/null 2>&1
}

legacy_present=false
if [[ -e "$legacy_plist" ]] || service_loaded "$legacy_service"; then legacy_present=true; fi
if $legacy_present && ! $migrate; then
  print -u2 "The legacy Outlook Meeting Alert service was found. Review the migration notes, then rerun ./install.sh --migrate."
  exit 1
fi

/bin/mkdir -p "$applications_dir" "$launch_agents_dir" "$logs_dir"
/bin/rm -rf "$candidate" "$previous_app"
/bin/rm -f "$pending_plist" "$previous_plist"
"$project_dir/build.sh" --output "$candidate"

"$project_dir/scripts/create-launch-agent-plist.sh" \
  "$pending_plist" "$app_path/Contents/MacOS/CalflareAgent" "$logs_dir"

if $legacy_present; then
  if [[ -f "$legacy_state" && ! -e "$data_dir/alerted-events.txt" ]]; then
    /bin/mkdir -p "$data_dir"
    migration_copy="$data_dir/.alerted-events.migration.$$"
    /bin/cp "$legacy_state" "$migration_copy"
    /bin/mv "$migration_copy" "$data_dir/alerted-events.txt"
  fi
  if service_loaded "$legacy_service"; then
    /bin/launchctl bootout "$legacy_service"
  fi
fi

calflare_was_loaded=false
if service_loaded "$service_name"; then
  calflare_was_loaded=true
  /bin/launchctl bootout "$service_name"
fi
[[ ! -e "$app_path" ]] || /bin/mv "$app_path" "$previous_app"
[[ ! -e "$plist_path" ]] || /bin/mv "$plist_path" "$previous_plist"
/bin/mv "$candidate" "$app_path"
/bin/mv "$pending_plist" "$plist_path"

if ! /bin/launchctl enable "$service_name" || ! /bin/launchctl bootstrap "gui/$(id -u)" "$plist_path"; then
  print -u2 "Calflare service could not be loaded; restoring the previous installation."
  /bin/rm -f "$plist_path"
  /bin/rm -rf "$app_path"
  [[ ! -e "$previous_app" ]] || /bin/mv "$previous_app" "$app_path"
  [[ ! -e "$previous_plist" ]] || /bin/mv "$previous_plist" "$plist_path"
  if $calflare_was_loaded && [[ -e "$plist_path" ]]; then
    /bin/launchctl bootstrap "gui/$(id -u)" "$plist_path" || print -u2 "Could not restore the previous Calflare service."
  fi
  if $legacy_present; then
    /bin/launchctl bootstrap "gui/$(id -u)" "$legacy_plist" || print -u2 "Could not restore the legacy service; see $legacy_plist."
  fi
  exit 1
fi

if $legacy_present; then /bin/rm -f "$legacy_plist"; fi
/bin/rm -rf "$previous_app"
/bin/rm -f "$previous_plist"
print "Installed and started $service_name from $app_path"
print "Calendar permission may need to be granted again for Calflare in System Settings > Privacy & Security > Calendars."
print "Ad-hoc signing does not guarantee Calendar permission retention after rebuilds."
