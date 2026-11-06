# Known issues

## Menu bar intermittently disappears after shortcut switching

Reported during global shortcut switching, while Command-Tab behaves normally. The cause is **not confirmed**, and the issue is not considered fixed.

Activation now uses `NSWorkspace.openApplication` after the non-modifier key-up event. This follows the modern cooperative activation path but has not proven to resolve the symptom.

Conditions to investigate:

- Key-up does not mean all modifier keys have been released; switching can occur while Option is still down.
- Different target applications can have overlapping activation requests. Only duplicate requests for the same pending target are suppressed.
- AppKit may report the menu bar as visible even if the user observes a rendering problem. Diagnostic flags alone cannot prove screen visibility.

Potential experiments include waiting for modifier release and coalescing pending requests to the latest target. These are not implemented fixes or established causes.

When reporting, include macOS version, target app/version, shortcut, full-screen/Space/multiple-display context, approximate occurrence time with time zone, and whether Command-Tab or a mouse click restores the menu bar. Attach only a small redacted log excerpt; do not upload your entire preferences or personal app list.

## Other limitations

- Specific-window selection and guaranteed minimized-window restoration are not implemented.
- Opening a running app may trigger its reopen behavior, including creating a window.
- macOS 14 is the deployment target, not a fully tested compatibility matrix.
- Ad-hoc builds are intended for local development, not signed/notarized distribution.
- The settings interface is currently Korean.
