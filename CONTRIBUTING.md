# Contributing

Calflare is a native macOS Swift Package with no third-party dependencies.
Changes should keep the overlay design and make Calendar access unnecessary
for automated tests.

## Local checks

```sh
swift test
swift build -c release
for script in build.sh install.sh uninstall.sh scripts/*.sh; do
  zsh -n "$script" || exit 1
done
./scripts/check-packaging.sh
```

The packaging check builds an ad-hoc-signed app, moves it to a path containing
spaces and `&`, and checks its plist, signature, and localized resources. It
does not launch a GUI or load a LaunchAgent. For a manual synthetic preview,
run `./build.sh` and then
`build/Calflare.app/Contents/MacOS/CalflareAgent --test`.

Before a public release, confirm the copyright attribution in `LICENSE` and
review the manual Calendar-permission and multi-display behavior on supported
macOS versions. Do not include real calendar data, identifiers, or logs in
tests, screenshots, or bug reports.
