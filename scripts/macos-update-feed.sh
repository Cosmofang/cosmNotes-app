#!/bin/bash
set -euo pipefail

archive="$1"
version="$2"
output="$3"
base_url="${4:-https://github.com/Cosmofang/cosmNotes-app/releases/download/v$version/}"
feed_workspace="$(mktemp -d -t cosmnotes-appcast)"
trap 'rm -rf "$feed_workspace"' EXIT
tools_archive="$feed_workspace/Sparkle-2.10.1.tar.xz"
tools_sha="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
curl -q -fsSL --retry 2 --max-time 60 \
    "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz" -o "$tools_archive"
printf '%s  %s\n' "$tools_sha" "$tools_archive" | shasum -a 256 -c -

mkdir "$feed_workspace/tools" "$feed_workspace/updates"
tar -xJf "$tools_archive" -C "$feed_workspace/tools" ./bin/generate_appcast ./bin/sign_update
cp "$archive" "$feed_workspace/updates/"
printf '%s\n' "$COSMNOTES_UPDATE_SIGNING_KEY" | "$feed_workspace/tools/bin/generate_appcast" \
    --ed-key-file - --maximum-deltas 0 --download-url-prefix "$base_url" "$feed_workspace/updates"
appcast="$feed_workspace/updates/appcast.xml"
printf '%s\n' "$COSMNOTES_UPDATE_SIGNING_KEY" | "$feed_workspace/tools/bin/sign_update" \
    --verify --ed-key-file - "$appcast"
cp "$appcast" "$output"
