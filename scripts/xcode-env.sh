#!/bin/bash
# Source this file so DEVELOPER_DIR also applies to the caller's commands.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1; then
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
        if [ -d "$candidate" ]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi
if ! xcodebuild -version >/dev/null 2>&1; then
    echo 'Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
    exit 1
fi
