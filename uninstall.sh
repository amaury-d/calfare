#!/bin/zsh

set -euo pipefail

readonly app_path="$HOME/Applications/Calflare.app"
readonly plist_path="$HOME/Library/LaunchAgents/com.calflare.agent.plist"
readonly service_name="gui/$(id -u)/com.calflare.agent"

if /bin/launchctl print "$service_name" >/dev/null 2>&1; then
  /bin/launchctl bootout "$service_name"
fi
/bin/rm -f "$plist_path"
/bin/rm -rf "$app_path"

print "Stopped and removed $service_name and $app_path."
print "Calflare configuration, deduplication state, and logs were preserved."
