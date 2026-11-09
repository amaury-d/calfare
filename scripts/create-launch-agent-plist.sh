#!/bin/zsh

set -euo pipefail

if (( $# != 3 )); then
  print -u2 "Usage: $0 <plist-path> <agent-binary> <logs-directory>"
  exit 2
fi

readonly plist_path="$1"
readonly agent_binary="$2"
readonly logs_dir="$3"
/bin/mkdir -p "${plist_path:h}"
/usr/bin/plutil -create xml1 "$plist_path"
/usr/libexec/PlistBuddy -c "Add :Label string com.calflare.agent" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $agent_binary" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :AbandonProcessGroup bool true" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :StartInterval integer 20" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $logs_dir/stdout.log" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $logs_dir/stderr.log" "$plist_path"
/usr/bin/plutil -lint "$plist_path"
