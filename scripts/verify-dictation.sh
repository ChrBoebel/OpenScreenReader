#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo 'Usage: scripts/verify-dictation.sh /absolute/Saywing.app/Contents/Resources/Dictation' >&2
  exit 2
fi
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
resource_dir=$(cd "$1" && pwd -P)
check_dir="$repo_dir/.build/dictation-checks"
mkdir -p "$check_dir"
xcrun swiftc -swift-version 6 -module-cache-path "$check_dir/modules" -parse-as-library \
  "$repo_dir/OpenScreenReaderApp/Dictation/DictationCore.swift" \
  "$repo_dir/Tests/Dictation/CoreChecks.swift" -o "$check_dir/core-checks"
"$check_dir/core-checks"
"$resource_dir/Python/bin/python3" -I -B "$repo_dir/Tests/Dictation/test_worker.py"
# Whisper Turbo is always bundled; other models are checked when this build bundles them.
"$resource_dir/Python/bin/python3" -I -B "$repo_dir/Tests/Dictation/integration_worker.py" "$resource_dir" "$check_dir" whisper-turbo
if [[ -d "$resource_dir/Model" ]]; then
  "$resource_dir/Python/bin/python3" -I -B "$repo_dir/Tests/Dictation/integration_worker.py" "$resource_dir" "$check_dir" qwen3-asr
fi
if [[ -d "$resource_dir/WhisperLargeV3" ]]; then
  "$resource_dir/Python/bin/python3" -I -B "$repo_dir/Tests/Dictation/integration_worker.py" "$resource_dir" "$check_dir" whisper-large-v3
fi
