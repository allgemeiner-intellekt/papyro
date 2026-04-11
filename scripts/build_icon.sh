#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=build/icon
mkdir -p "$BUILD/AppIcon.iconset"

swift scripts/render_icon.swift "$BUILD/icon_1024.png"

for size in 16 32 64 128 256 512; do
  sips -z $size $size "$BUILD/icon_1024.png" --out "$BUILD/icon_${size}.png" >/dev/null
done

cp "$BUILD/icon_16.png"   "$BUILD/AppIcon.iconset/icon_16x16.png"
cp "$BUILD/icon_32.png"   "$BUILD/AppIcon.iconset/icon_16x16@2x.png"
cp "$BUILD/icon_32.png"   "$BUILD/AppIcon.iconset/icon_32x32.png"
cp "$BUILD/icon_64.png"   "$BUILD/AppIcon.iconset/icon_32x32@2x.png"
cp "$BUILD/icon_128.png"  "$BUILD/AppIcon.iconset/icon_128x128.png"
cp "$BUILD/icon_256.png"  "$BUILD/AppIcon.iconset/icon_128x128@2x.png"
cp "$BUILD/icon_256.png"  "$BUILD/AppIcon.iconset/icon_256x256.png"
cp "$BUILD/icon_512.png"  "$BUILD/AppIcon.iconset/icon_256x256@2x.png"
cp "$BUILD/icon_512.png"  "$BUILD/AppIcon.iconset/icon_512x512.png"
cp "$BUILD/icon_1024.png" "$BUILD/AppIcon.iconset/icon_512x512@2x.png"

iconutil -c icns "$BUILD/AppIcon.iconset" -o Papyro/Resources/AppIcon.icns
echo "wrote Papyro/Resources/AppIcon.icns"
