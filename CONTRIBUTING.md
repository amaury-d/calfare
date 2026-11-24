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
The menu bar item and the Calendars window need a GUI session and Calendar
access, so test them manually (`make install`). Run `make preview` for a
synthetic full-screen alert, and `make icon` to regenerate the committed logo
resources (`App/Resources/AppIcon.icns`, `StatusIcon.pdf` and `docs/icon.png`)
after editing `scripts/make-icon.swift`. Regenerating rewrites the PDF even
when the drawing is unchanged, so only commit it when the logo really changed.

The launch-at-login states are testable from a terminal without clicking:
`CalflareAgent --login-item-status` prints `managed-by-launch-agent`,
`disabled`, `enabled`, `requires-approval` or `unavailable-*`, and
`--enable-login-item` / `--disable-login-item` register and unregister. `make clean` removes
the Swift build cache and `build/Calflare.app`, not other files in `build/`.

Before a public release, confirm the copyright attribution in `LICENSE` and
review the manual Calendar-permission and multi-display behavior on supported
macOS versions. Do not include real calendar data, identifiers, or logs in
tests, screenshots, or bug reports.
