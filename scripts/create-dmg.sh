#!/bin/bash
set -euo pipefail

# Usage: ./scripts/create-dmg.sh <app_path> <output_dmg_path> [volume_name]
# Example: ./scripts/create-dmg.sh build/SuperCloudys.app build/SuperCloudys-v1.0.0.dmg SuperCloudys

APP_PATH="${1:?Usage: create-dmg.sh <app_path> <output_dmg_path> [volume_name]}"
OUTPUT_DMG="${2:?Usage: create-dmg.sh <app_path> <output_dmg_path> [volume_name]}"
VOLUME_NAME="${3:-SuperCloudys}"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH not found"
  exit 1
fi

STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Preparing DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG: $OUTPUT_DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "DMG created: $OUTPUT_DMG"
echo "Size: $(du -h "$OUTPUT_DMG" | cut -f1)"
