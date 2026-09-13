#!/bin/zsh
# assets/ShotScribe-icon-1024.png → assets/ShotScribe.iconset + assets/ShotScribe.icns.
# The master comes from scripts/fit-icon.swift (Josh's artwork on Apple's grid).
set -euo pipefail
cd "$(dirname "$0")/.."
MASTER=assets/ShotScribe-icon-1024.png
SET=assets/ShotScribe.iconset
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$MASTER" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$MASTER" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/ShotScribe.icns
echo "==> $SET and assets/ShotScribe.icns from $MASTER"
