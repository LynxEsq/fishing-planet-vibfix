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

# Find dylib and launcher — prefer pre-built from build/, fall back to local, then compile
DYLIB=""
LAUNCHER=""

if [ -f "$SCRIPT_DIR/build/vibration_fix.dylib" ] && [ -f "$SCRIPT_DIR/build/launcher" ]; then
    echo "Using pre-built binaries from build/"
    DYLIB="$SCRIPT_DIR/build/vibration_fix.dylib"
    LAUNCHER="$SCRIPT_DIR/build/launcher"
elif [ -f "$SCRIPT_DIR/vibration_fix.dylib" ] && [ -f "$SCRIPT_DIR/launcher" ]; then
    echo "Using locally built binaries"
    DYLIB="$SCRIPT_DIR/vibration_fix.dylib"
    LAUNCHER="$SCRIPT_DIR/launcher"
else
    echo "No pre-built binaries found. Building from source..."
    echo "(requires Xcode Command Line Tools: xcode-select --install)"
    make -C "$SCRIPT_DIR" all
    DYLIB="$SCRIPT_DIR/vibration_fix.dylib"
    LAUNCHER="$SCRIPT_DIR/launcher"
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
cp "$LAUNCHER" "$GAME_BIN"
chmod +x "$GAME_BIN"

# Ensure dylib is in project root
if [ "$DYLIB" != "$SCRIPT_DIR/vibration_fix.dylib" ]; then
    cp "$DYLIB" "$SCRIPT_DIR/vibration_fix.dylib"
fi

# Write dylib path for the launcher to find
echo "$SCRIPT_DIR/vibration_fix.dylib" > "$GAME_MACOS/.vibfix_dylib_path"
echo "Wrote dylib path: $SCRIPT_DIR/vibration_fix.dylib"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Files:"
echo "  Dylib:    $SCRIPT_DIR/vibration_fix.dylib"
echo "  Config:   $SCRIPT_DIR/config.txt"
echo "  Log:      $SCRIPT_DIR/vibfix.log (created on game launch)"
echo "  Launcher: $GAME_BIN"
echo "  Backup:   $REAL_BIN"
echo ""
echo "IMPORTANT — next steps:"
echo ""
echo "  1. Enable Steam Input:"
echo "     Steam > Fishing Planet > Properties > Controller > Enable Steam Input"
echo ""
echo "  2. Reset Input Monitoring permission:"
echo "     System Settings > Privacy & Security > Input Monitoring"
echo "     Remove FishingPlanet, then re-launch — macOS will ask again."
echo ""
echo "  3. Launch the game. A short test vibration = it works!"
echo ""
echo "Edit config.txt to customize vibration strength."
echo "Changes apply on next game restart."
