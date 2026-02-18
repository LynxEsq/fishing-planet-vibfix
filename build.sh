#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Fishing Planet Vibration Fix — Build ==="
echo ""

# Check for Xcode Command Line Tools
if ! xcode-select -p &>/dev/null; then
    echo "ERROR: Xcode Command Line Tools not installed."
    echo ""
    echo "Install them with:"
    echo "  xcode-select --install"
    exit 1
fi

echo "Building from source..."
make -C "$SCRIPT_DIR" clean all

echo ""
echo "=== Build complete ==="
echo ""
echo "Files:"
echo "  $SCRIPT_DIR/build/vibration_fix.dylib"
echo "  $SCRIPT_DIR/build/launch"
echo "  $SCRIPT_DIR/VibFix.app"
echo ""
echo "To install, run: ./scripts/install.sh"
