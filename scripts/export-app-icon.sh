#!/bin/sh
set -eu

# Export the approved artwork without changing its geometry, colours or padding.
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$project_dir/docs/brand-identity/assets/saywing-app-icon.png"
output_dir="$project_dir/OpenScreenReaderApp/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$output_dir"
for size in 16 32 64 128 256 512 1024; do
    /usr/bin/sips --resampleHeightWidth "$size" "$size" "$source_icon" \
        --out "$output_dir/icon_${size}.png" >/dev/null
done

# Monochrome template; AppKit chooses the foreground for light/dark menu bars.
menu_dir="$project_dir/OpenScreenReaderApp/Assets.xcassets/SaywingMenuBar.imageset"
for scale in 1 2 3; do
    size=$((22 * scale))
    /usr/bin/sips --resampleHeightWidth "$size" "$size" \
        "$project_dir/docs/brand-identity/assets/saywing-menubar.png" \
        --out "$menu_dir/mark-${scale}x.png" >/dev/null
done
