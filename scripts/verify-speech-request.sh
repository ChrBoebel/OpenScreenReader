#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
mkdir -p "$repo_dir/.build"
xcrun swiftc -swift-version 6 -parse-as-library \
    "$repo_dir/Runtime/Sources/SpeechWorker/SpeechWorkerRequest.swift" \
    "$repo_dir/Tests/Fixtures/SpeechRequestChecks.swift" \
    -o "$repo_dir/.build/speech-request-checks"
"$repo_dir/.build/speech-request-checks"
