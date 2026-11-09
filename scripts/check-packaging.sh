#!/bin/zsh

set -euo pipefail

readonly project_dir="${0:A:h:h}"
readonly fixture="$project_dir/.packaging-check/Calflare & relocated.app"
readonly moved="$project_dir/.packaging-check/relocated path/Calflare & relocated.app"
trap '/bin/rm -rf "$project_dir/.packaging-check"' EXIT

/bin/rm -rf "$project_dir/.packaging-check"
"$project_dir/build.sh" --output "$fixture"
/bin/mkdir -p "${moved:h}"
/bin/mv "$fixture" "$moved"

/usr/bin/plutil -lint "$moved/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$moved"
[[ -x "$moved/Contents/MacOS/CalflareAgent" ]]
[[ -x "$moved/Contents/MacOS/CalflareOverlay" ]]
[[ -f "$moved/Contents/Resources/Calflare_CalflareOverlay.bundle/Contents/Resources/en.lproj/Localizable.strings" ]]
[[ -f "$moved/Contents/Resources/Calflare_CalflareOverlay.bundle/Contents/Resources/fr.lproj/Localizable.strings" ]]
resource_output=$("$moved/Contents/MacOS/CalflareOverlay" -AppleLanguages '(en)' --check-resources)
[[ "$resource_output" == *"Join Teams"* ]]
[[ "$resource_output" == *"Calflare preview"* ]]
french_output=$("$moved/Contents/MacOS/CalflareOverlay" -AppleLanguages '(fr)' --check-resources)
[[ "$french_output" == *"Rejoindre Teams"* ]]
[[ "$french_output" == *"Aperçu de Calflare"* ]]

plist="$project_dir/.packaging-check/launch agents & logs/Calflare.plist"
binary="$project_dir/.packaging-check/Applications & data/Calflare.app/Contents/MacOS/CalflareAgent"
logs="$project_dir/.packaging-check/Logs & records"
/bin/mkdir -p "${plist:h}"
"$project_dir/scripts/create-launch-agent-plist.sh" "$plist" "$binary" "$logs"
/usr/bin/plutil -lint "$plist"
[[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$plist")" == "$binary" ]]
[[ "$(/usr/bin/plutil -extract StandardOutPath raw -o - "$plist")" == "$logs/stdout.log" ]]
print "Packaging smoke check passed after relocation."
