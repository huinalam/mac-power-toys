# Mac Power Toys

English | [한국어](docs/README.ko.md)

A native macOS menu bar utility built with SwiftUI and AppKit, inspired by Microsoft PowerToys. It provides app shortcuts inspired by [Thor](https://github.com/gbammc/Thor) and an optional icon-and-title window switcher.

**Early development preview.** An intermittent menu bar disappearance during shortcut switching is still under investigation. See [known issues](docs/KNOWN_ISSUES.md). This is an independent project, not an official Microsoft or Apple product.

## Features

- Add applications and record a global shortcut for each one.
- Launch stopped apps or bring running apps to the foreground.
- Prevent duplicate shortcuts within the app, including disabled entries.
- Enable shortcuts individually or pause all shortcuts.
- Keep settings across launches and optionally start at login.
- Use Option-Tab to choose individual windows by app icon and title, without thumbnails.
- Inspect small, local diagnostic logs to help investigate switching issues.

The current settings UI is in Korean; shortcut recorder text follows the dependency's localization.

## Requirements

- Deployment target: macOS 14 or later.
- Build tools: full Xcode with Swift 6.2 or later. Command Line Tools alone lack required SwiftUI macro plugins.
- Network access for the first dependency download.

Manual development checks have been performed on macOS 27.0.1 / Apple Silicon. This is not a claim that all supported OS versions and Intel Macs have been manually verified.

## Build and run

```sh
git clone https://github.com/huinalam/mac-power-toys.git
cd mac-power-toys
./scripts/build-app.sh
open "dist/Mac Power Toys.app"
```

The script builds a Universal app with a local ad-hoc signature. It does **not** perform Developer ID signing or notarization. This initial publication distributes source, not a release binary.

Scripts use the selected Xcode, or discover an installation under `/Applications` if Command Line Tools are selected. Set `DEVELOPER_DIR` to explicitly choose an installation. They do not change the system-wide Xcode selection. The packaging script currently uses SwiftPM's Xcode build system; newer toolchains may print a deprecation warning for that option.

To use start at login, move the app to `/Applications` and launch it there before enabling the option. You can also open `Package.swift` in Xcode for editing.

## Use

1. Choose **앱 추가** (Add app) in settings.
2. Click the shortcut recorder beside the app and press a key combination.
3. Press the shortcut to launch or switch immediately on key-down; releasing modifiers is not required.
4. Close settings; the app stays in the menu bar. Use the ⌘ icon to reopen settings, pause shortcuts, or quit.

While an open request is in flight, a new request replaces the previous pending target. Open requests are serialized; an already-submitted system operation cannot be cancelled. Caps Lock does not block switching.

The play button tests launching even when shortcuts are paused. Removing an entry does not delete the actual application. An already-active app is left unchanged. Settings are stored locally in UserDefaults.

Activation uses `NSWorkspace.openApplication`. The target app may open a new window in response to a reopen event. App shortcuts select an application, while the optional window switcher selects a specific window with Accessibility permission. Forced Space movement and guaranteed restoration of minimized windows are not implemented. App shortcuts alone do not require Accessibility permission; Input Monitoring and Screen Recording are not requested. Conflicts with every other application's shortcuts cannot be detected.

## Option-Tab window switcher

Enable **⌥Tab 창 전환기** in settings, then use **권한 요청** (Request permission) to grant Accessibility access in System Settings. Return to settings and click **다시 확인** (Check again). Install the app in a stable location before granting access; rebuilding an ad-hoc signed app can require renewed permission.

- Hold Option and press Tab to show the list and select the next window.
- Continue pressing Tab, or Shift-Tab to move backwards.
- Release Option (or press Enter) to switch to the selected window; Escape cancels.
- Arrow keys also move the selection. The overlay does not activate the utility itself.
- App shortcuts retain their immediate key-down behavior. Global pause also pauses the window switcher.
- Option-Tab and Shift-Option-Tab are reserved while the feature is enabled. Existing app shortcut conflicts must be resolved first; nothing is silently overwritten. Other window-switcher utilities using these keys should be disabled or configured differently.

The first version lists standard windows and dialogs matched to on-screen, normal-layer windows across the current visible displays. Hidden apps, minimized windows, other Spaces, and special utility windows are outside the supported scope. Public APIs do not expose a universal mapping between Accessibility windows and WindowServer IDs: this implementation matches process and bounds, so unusual or identical-geometry windows can be omitted or ambiguous. Recent focus history is kept in memory; unobserved windows fall back to front-to-back order. A slow app may be omitted after the bounded enumeration pass. See [known issues](docs/KNOWN_ISSUES.md).

This feature uses public Accessibility and CoreGraphics metadata APIs. It does not capture screen images, request screen recording, or use AltTab source/private APIs. Window titles exist in memory for display and are not added to diagnostic logs.

## Diagnostics and privacy

Diagnostic records stay in `~/Library/Logs/MacPowerToys/activation.jsonl`. The app does not upload them or send analytics.

- Retention: 24 hours and a maximum of 256 KiB, deleting oldest records first.
- Cleanup: on startup, on writes, and every 15 minutes while running; expired records are removed on the next launch if the app was stopped.
- Contents: timestamps, app bundle IDs/PIDs, activation and menu bar state, modifier flags, and error codes. No window titles, document contents, typed characters, or full app paths are recorded.
- Diagnostic events are not duplicated into the system log; file-write failures can be logged there.

Use **진단 로그 폴더 열기…** (Open diagnostic log folder) to inspect logs and **메뉴 막대 문제 시점 기록** (Mark menu bar issue) after an occurrence. The marker reflects when you clicked it, not necessarily when the symptom began. Review and redact app identifiers before attaching excerpts to a public issue. See [diagnostic interpretation](docs/README.ko.md#앱-전환-진단-로그).

## Development

```sh
./scripts/test.sh
./scripts/build-app.sh
```

- `AppStore`: app registration, shortcut handlers, launching, login items.
- `AppEntry` / `SettingsRepository`: app identity and settings persistence.
- `SettingsView`: SwiftUI settings interface.
- `AppDelegate`: menu bar and settings window lifecycle.
- `ActivationDiagnostics`: bounded local diagnostic recording.
- `WindowSwitcherController` / `WindowSelection`: optional switcher session, keyboard navigation, and focus history.
- `WindowAccess`: bounded Accessibility queries on a serial worker queue and exact-window raise requests.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for test coverage and the manual verification checklist. Commit `Package.resolved` to keep dependency resolution reproducible.

## License and credits

[MIT](LICENSE). [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) supplies shortcut registration and recording under its own MIT license. See [third-party notices](THIRD_PARTY_NOTICES.md). Thor inspired the interaction; no Thor source code is included.
