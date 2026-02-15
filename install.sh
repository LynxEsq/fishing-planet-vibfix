#!/bin/bash
set -e

GAME_APP="$HOME/Library/Application Support/Steam/steamapps/common/Fishing Planet/FishingPlanet.app"
GAME_MACOS="$GAME_APP/Contents/MacOS"
GAME_BIN="$GAME_MACOS/FishingPlanet"
REAL_BIN="$GAME_MACOS/FishingPlanet_real"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Fishing Planet Vibration Fix — Installer ==="
echo ""

# Check game exists
if [ ! -d "$GAME_APP" ]; then
    echo "ERROR: Game not found at:"
    echo "  $GAME_APP"
    echo ""
    echo "Make sure Fishing Planet is installed via Steam."
    exit 1
fi

# Build if needed
if [ ! -f "$SCRIPT_DIR/vibration_fix.dylib" ] || [ ! -f "$SCRIPT_DIR/launcher" ]; then
    echo "Building..."
    make -C "$SCRIPT_DIR" all
fi

# Backup original binary (only if not already done)
if [ ! -f "$REAL_BIN" ]; then
    echo "Backing up original binary..."
    cp "$GAME_BIN" "$REAL_BIN"
    echo "  Saved: $REAL_BIN"
else
    echo "Original binary already backed up."
fi

# Install launcher
echo "Installing launcher..."
cp "$SCRIPT_DIR/launcher" "$GAME_BIN"
chmod +x "$GAME_BIN"

# Copy config if it doesn't exist yet in install dir
if [ ! -f "$SCRIPT_DIR/config.txt" ]; then
    echo "WARNING: config.txt not found — using built-in defaults."
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Files:"
echo "  Dylib:    $SCRIPT_DIR/vibration_fix.dylib"
echo "  Config:   $SCRIPT_DIR/config.txt"
echo "  Log:      $SCRIPT_DIR/vibfix.log"
echo "  Launcher: $GAME_BIN"
echo "  Backup:   $REAL_BIN"
echo ""
echo "IMPORTANT: Enable Steam Input for the game:"
echo "  Steam > Fishing Planet > Properties > Controller"
echo "  Set to 'Enable Steam Input' or 'Use default settings'"
echo ""
echo "Edit config.txt to customize vibration strength."
echo "Changes apply on next game restart."
