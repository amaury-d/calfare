# Contributing

Calflare is a native macOS Swift Package with no third-party dependencies.
Changes should keep the overlay design and make Calendar access unnecessary
for automated tests.

## Local checks

```sh
make check
```

This runs the tests, builds an ad-hoc-signed app, and checks its property
lists, localized resources, and signature without Calendar access or a GUI.
`App/` contains the bundle metadata, translations, and LaunchAgent template.
Run `make preview` for a synthetic full-screen alert. `make clean` removes
the Swift build cache and `build/Calflare.app`, not other files in `build/`.

Before a public release, confirm the copyright attribution in `LICENSE` and
review the manual Calendar-permission and multi-display behavior on supported
macOS versions. Do not include real calendar data, identifiers, or logs in
tests, screenshots, or bug reports.
