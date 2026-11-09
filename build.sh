#!/bin/zsh

set -euo pipefail

readonly project_dir="${0:A:h}"
output="$project_dir/build/Calflare.app"
while (( $# )); do
  case "$1" in
    --output)
      (( $# >= 2 )) || { print -u2 "Missing value for --output"; exit 2; }
      output="$2"
      shift 2
      ;;
    *)
      print -u2 "Unknown argument: $1"
      exit 2
      ;;
  esac
done

readonly output="${output:A}"
[[ "$output" == *.app && "$output" != "$HOME" && "$output" != "$project_dir" ]] || {
  print -u2 "Output must be an app bundle path ending in .app."
  exit 2
}
if [[ -e "$output" && ! -f "$output/Contents/Info.plist" ]]; then
  print -u2 "Refusing to replace a directory that is not an app bundle: $output"
  exit 2
fi
readonly output_parent="${output:h}"
readonly staging="${output}.staging.$$"
trap '[[ -d "$staging" ]] && /bin/rm -rf "$staging"' EXIT

/bin/mkdir -p "$output_parent"
/usr/bin/swift build --package-path "$project_dir" --configuration release \
  --scratch-path "$project_dir/.swift-build"
bin_dir=$(/usr/bin/swift build --package-path "$project_dir" --configuration release \
  --scratch-path "$project_dir/.swift-build" --show-bin-path)

/bin/mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
/bin/cp "$bin_dir/CalflareAgent" "$staging/Contents/MacOS/CalflareAgent"
/bin/cp "$bin_dir/CalflareOverlay" "$staging/Contents/MacOS/CalflareOverlay"
/bin/cp "$project_dir/Sources/CalflareAgent/Info.plist" "$staging/Contents/Info.plist"
/bin/cp -R "$project_dir/Sources/CalflareAgent/Resources/" "$staging/Contents/Resources/"
resource_bundle="$bin_dir/Calflare_CalflareOverlay.bundle"
[[ -d "$resource_bundle" ]] || { print -u2 "Missing SwiftPM localization resource bundle."; exit 1; }
/bin/cp -R "$resource_bundle" "$staging/Contents/Resources/"

/usr/bin/plutil -lint "$staging/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - --identifier com.calflare.agent "$staging"
/usr/bin/codesign --verify --deep --strict "$staging"

if [[ -e "$output" ]]; then /bin/rm -rf "$output"; fi
/bin/mv "$staging" "$output"
trap - EXIT
print "Built signed Calflare app: $output"
