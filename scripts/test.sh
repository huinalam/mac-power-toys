#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/xcode-env.sh
swift test "$@"
