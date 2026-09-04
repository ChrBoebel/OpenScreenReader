#!/bin/bash
# A separate app is required: screen capture excludes OpenScreenReader's own windows.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
fixture_dir="$repo_dir/.build/SpeechFixture.app"
[[ ! -L "$fixture_dir" ]] || exit 2
if [[ -e "$fixture_dir" ]]; then
    [[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$fixture_dir/Contents/Info.plist") == com.christopherbobel.OpenScreenReader.SpeechFixture ]] || exit 2
fi
mkdir -p "$fixture_dir/Contents/MacOS"
cp "$repo_dir/Tests/Fixtures/SpeechFixture-Info.plist" "$fixture_dir/Contents/Info.plist"
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos14.0 \
    "$repo_dir/Tests/Fixtures/SpeechFixture.swift" -o "$fixture_dir/Contents/MacOS/SpeechFixture"
codesign --force --sign - "$fixture_dir"
echo "Built the separate, fixed-text speech fixture."
