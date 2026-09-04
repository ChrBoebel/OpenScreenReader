#!/bin/bash
# Explicit development-only download; never called by the application runtime.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ( $# -eq 2 && "$2" != --verify-only ) ]]; then
    echo "Usage: bash scripts/download-qwen.sh ABSOLUTE_DIRECTORY_OUTSIDE_GIT [--verify-only]" >&2
    exit 2
fi
script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(cd "$script_dir/.." && pwd -P)
manifest="$repo_dir/docs/research/qwen-download-manifest.json"
jq -e '
    .schemaVersion == 1 and
    .repository == "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit" and
    (.files | length > 0) and
    ([.files[].bytes] | add) == .expectedTotalBytes and
    all(.files[]; (.bytes > 0 and .bytes == (.bytes | floor)) and
        (.path | test("^[A-Za-z0-9_./-]+$")) and
        (if .sha256 then (.sha256 | test("^[0-9a-f]{64}$"))
         else (.gitBlobSHA1 | test("^[0-9a-f]{40}$")) end))
' "$manifest" >/dev/null
destination="$1"
[[ "$destination" == /* && "$destination" != / && ! -L "$destination" ]] || exit 2
if [[ "${2:-}" == --verify-only ]]; then
    [[ -d "$destination" ]] || { echo "Model directory is missing." >&2; exit 1; }
else
    mkdir -p "$destination"
fi
destination=$(cd "$destination" && pwd -P)
case "$destination/" in "$repo_dir/"*) echo "Weights must remain outside the repository." >&2; exit 2;; esac
if git -C "$destination" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Refusing to place weights inside a Git worktree." >&2
    exit 2
fi
revision=$(jq -er .revision "$manifest")
repository=$(jq -er .repository "$manifest")
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || exit 2

verify_file() {
    local file="$1" bytes="$2" algorithm="$3" expected="$4" actual
    [[ -f "$file" && ! -L "$file" ]] || return 1
    [[ $(stat -f %z "$file") == "$bytes" ]] || return 1
    if [[ "$algorithm" == sha256 ]]; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        actual=$(git hash-object --no-filters "$file")
    fi
    [[ "$actual" == "$expected" ]]
}

while IFS=$'\t' read -r path bytes algorithm expected; do
    [[ "$path" != /* && "$path" != *..* ]] || exit 2
    file="$destination/$path"
    [[ ! -L "$file" && ! -L "$file.part" ]] || exit 2
    if [[ "${2:-}" != --verify-only ]]; then mkdir -p "$(dirname "$file")"; fi
    parent=$(cd "$(dirname "$file")" && pwd -P)
    [[ "$parent/" == "$destination/"* ]] || exit 2
    if ! verify_file "$file" "$bytes" "$algorithm" "$expected"; then
        if [[ -e "$file" || "${2:-}" == --verify-only ]]; then
            echo "Missing or invalid file: $path; no existing file overwritten." >&2
            exit 1
        fi
        echo "Downloading $path ($bytes bytes)"
        curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
            --connect-timeout 30 --max-time 3600 --speed-limit 1024 --speed-time 60 \
            --retry 3 --continue-at - --output "$file.part" \
            "https://huggingface.co/$repository/resolve/$revision/$path"
        verify_file "$file.part" "$bytes" "$algorithm" "$expected" || {
            echo "Integrity mismatch for $path; leaving .part untrusted." >&2; exit 1;
        }
        mv -n "$file.part" "$file"
    fi
    echo "Verified $path"
done < <(jq -er '.files[] | [.path, .bytes, (if .sha256 then "sha256" else "gitBlobSHA1" end), (.sha256 // .gitBlobSHA1)] | @tsv' "$manifest")
echo "All pinned model files verified. No inference runtime has been installed or executed."
