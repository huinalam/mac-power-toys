# Known issues

## Menu bar intermittently disappears after shortcut switching

Reported during global shortcut switching, while Command-Tab behaves normally. The cause is **not confirmed**, and the issue is not considered fixed.

Activation uses `NSWorkspace.openApplication`. Shortcuts trigger immediately on key-down. A modifier-release wait and 50 ms quiet period were tried but removed because they made switching feel unresponsive. Only the latest pending target is retained. Submitted open requests are serialized until their completion callback; already-submitted system operations cannot be cancelled, and callback completion does not guarantee visual activation has finished.

Pausing shortcuts, disabling an entry, or removing an entry cancels matching pending shortcut requests. Manual launch buttons work while shortcuts are paused.

Serialization addresses overlapping open requests. Switching while modifiers are held remains intentional for immediate response. They are **not yet proof that the menu bar symptom is resolved**. AppKit may report the menu bar as visible even if the user observes a rendering problem.

When reporting, include macOS version, target app/version, shortcut, full-screen/Space/multiple-display context, approximate occurrence time with time zone, and whether Command-Tab or a mouse click restores the menu bar. Attach only a small redacted log excerpt; do not upload your entire preferences or personal app list.

## Other limitations

- The optional window switcher supports on-screen standard windows/dialogs. Hidden/minimized/other-Space windows are not supported.
- AX-to-WindowServer matching uses PID and bounds, so identical-geometry windows may be ambiguous; public APIs do not guarantee coverage for every app.
- Focus history begins when the feature is enabled; missing history uses window stacking order.
- Accessibility permission must be granted manually. Revoked permission disables window enumeration; ad-hoc rebuilds may require granting permission again.
- The switcher uses raise/activation requests. Their acceptance does not guarantee every target app will focus the requested window.
- Full-screen and multiple-display edge cases need additional manual verification.
- Opening a running app may trigger its reopen behavior, including creating a window.
- macOS 14 is the deployment target, not a fully tested compatibility matrix.
- Ad-hoc builds are intended for local development, not signed/notarized distribution.
- The settings interface is currently Korean.
