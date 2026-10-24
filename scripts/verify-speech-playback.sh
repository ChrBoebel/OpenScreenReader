#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
mkdir -p "$repo_dir/.build"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos14.0 \
    "$repo_dir/OpenScreenReaderApp/LocalSpeechService.swift" \
    "$repo_dir/OpenScreenReaderApp/WorkerSandbox.swift" \
    "$repo_dir/Tests/Fixtures/SpeechPlaybackProbe.swift" \
    -o "$repo_dir/.build/speech-playback-probe"
"$repo_dir/.build/speech-playback-probe" "$@"
runtime_args=()
for argument in "$@"; do
    case "$argument" in --bundled-root=*) runtime_args+=("$argument");; esac
done
"$repo_dir/.build/speech-playback-probe" "${runtime_args[@]}" --cancel
"$repo_dir/.build/speech-playback-probe" "${runtime_args[@]}" --cancel-loading
