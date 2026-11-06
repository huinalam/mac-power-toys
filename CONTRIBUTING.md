# Contributing

Small fixes, reproducible bug reports, and focused proposals are welcome. Discuss major changes in an issue before investing in implementation.

## Setup and checks

Install full Xcode with Swift 6.2 or newer, clone the repository, then run from its root:

```sh
./scripts/test.sh
./scripts/build-app.sh
```

`DEVELOPER_DIR` can select a particular Xcode. Scripts never modify the system-wide selection. `Package.resolved` is tracked. CI runs tests, packages the app, and verifies its local signature; it does not publish binaries or validate interactive UI behavior.

Keep changes focused and add regression tests for meaningful behavior changes. Existing automated tests cover persistence, duplicate shortcut validation, pause state, missing apps, corrupt settings preservation, log serialization, retention, and size limits. They do not prove global shortcut behavior or menu bar rendering.

## Manual verification

- Add an app, assign/change/remove a shortcut, and check duplicate rejection.
- Switch from another app; launch a stopped app; activate a hidden app.
- Check already-active apps, rapid switching, and modifier-key release.
- Check individual disable, global pause, and persistence after restarting.
- Close settings and confirm menu bar operation continues.
- Test deleted/moved targets, Korean/English input sources, multiple displays, Spaces, full screen, and minimized windows.
- Test login-item approval only in an installed app where appropriate.

## Pull requests and privacy

Describe the observed problem, resulting behavior, tests, and remaining limitations. Do not claim the menu bar issue is fixed without reproduction and verification.

Never commit local settings, real diagnostic logs, credentials, certificates, build outputs, or identifying screenshots. Use synthetic fixtures in tests. Bug reports should contain only relevant, reviewed log excerpts.

Contributions are provided under the project's MIT license. Preserve third-party notices.
