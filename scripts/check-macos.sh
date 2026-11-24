#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

binary_dir="$(swift build -c release --show-bin-path)"
for check in CosmNotesWorkChecks StickyNotesGeometryChecks; do
    swift build -c release --product "$check"
    executable="$binary_dir/$check"
    # Use the same ad-hoc signing step as the app for executables on hosted macOS runners.
    codesign --force --sign - "$executable"
    codesign --verify --strict "$executable"
    "$executable"
done
