# Known issues

## Menu bar intermittently disappears after shortcut switching

Reported during global shortcut switching, while Command-Tab behaves normally. The cause is **not confirmed**, and the issue is not considered fixed.

Activation uses `NSWorkspace.openApplication`. Shortcuts trigger immediately on key-down. A modifier-release wait and 50 ms quiet period were tried but removed because they made switching feel unresponsive. Only the latest pending target is retained. Submitted open requests are serialized until their completion callback; already-submitted system operations cannot be cancelled, and callback completion does not guarantee visual activation has finished.

Pausing shortcuts, disabling an entry, or removing an entry cancels matching pending shortcut requests. Manual launch buttons work while shortcuts are paused.

Serialization addresses overlapping open requests. Switching while modifiers are held remains intentional for immediate response. They are **not yet proof that the menu bar symptom is resolved**. AppKit may report the menu bar as visible even if the user observes a rendering problem.

When reporting, include macOS version, target app/version, shortcut, full-screen/Space/multiple-display context, approximate occurrence time with time zone, and whether Command-Tab or a mouse click restores the menu bar. Attach only a small redacted log excerpt; do not upload your entire preferences or personal app list.

## Other limitations

- Specific-window selection and guaranteed minimized-window restoration are not implemented.
- Opening a running app may trigger its reopen behavior, including creating a window.
- macOS 14 is the deployment target, not a fully tested compatibility matrix.
- Ad-hoc builds are intended for local development, not signed/notarized distribution.
- The settings interface is currently Korean.
