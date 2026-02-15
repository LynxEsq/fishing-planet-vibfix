#!/bin/bash
set -e

GAME_APP="$HOME/Library/Application Support/Steam/steamapps/common/Fishing Planet/FishingPlanet.app"
GAME_MACOS="$GAME_APP/Contents/MacOS"
GAME_BIN="$GAME_MACOS/FishingPlanet"
REAL_BIN="$GAME_MACOS/FishingPlanet_real"

echo "=== Fishing Planet Vibration Fix — Uninstaller ==="
echo ""

if [ ! -f "$REAL_BIN" ]; then
    echo "Nothing to uninstall (original binary backup not found)."
    exit 0
fi

echo "Restoring original binary..."
mv "$REAL_BIN" "$GAME_BIN"

echo ""
echo "=== Uninstall complete ==="
echo "Original game binary restored."
echo ""
echo "Note: vibration_fix.dylib and config.txt were NOT deleted."
echo "To fully remove, delete this directory."
