#!/bin/bash
set -e

APP_ID="380600"
STEAM_DIR="$HOME/Library/Application Support/Steam"
USERDATA_DIR="$STEAM_DIR/userdata"
GAME_MACOS="$STEAM_DIR/steamapps/common/Fishing Planet/FishingPlanet.app/Contents/MacOS"

echo "=== Fishing Planet Vibration Fix — Uninstaller ==="
echo ""

# ── Restore original binary if old install method was used ──
REAL_BIN="$GAME_MACOS/FishingPlanet_real"
if [ -f "$REAL_BIN" ]; then
    echo "Restoring original game binary..."
    mv "$REAL_BIN" "$GAME_MACOS/FishingPlanet"
    rm -f "$GAME_MACOS/.vibfix_dylib_path"
    echo "[OK] Original binary restored"
fi

# ── Remove Launch Options from Steam config ──
if [ "$VIBFIX_SKIP_STEAM_CHECK" != "1" ] && pgrep -fi "Steam" > /dev/null 2>&1; then
    echo ""
    echo "Steam is running. Please close Steam and re-run to remove Launch Options."
    echo "(Game binary was restored if needed.)"
    exit 1
fi

REMOVED=0
for user_dir in "$USERDATA_DIR"/*/; do
    vdf="$user_dir/config/localconfig.vdf"
    if [ -f "$vdf" ] && grep -q '"LaunchOptions".*vibfix' "$vdf" 2>/dev/null; then
        python3 << PYEOF
import os

vdf_path = "$vdf"
with open(vdf_path, 'r', encoding='utf-8', errors='replace') as f:
    lines = f.readlines()

new_lines = [l for l in lines if not ('"LaunchOptions"' in l and 'vibfix' in l)]

if len(new_lines) != len(lines):
    with open(vdf_path, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print(f"  Removed LaunchOptions from: {vdf_path}")
PYEOF
        REMOVED=1
    fi
done

if [ $REMOVED -eq 1 ]; then
    echo "[OK] Launch Options removed from Steam config"
else
    echo "[OK] No Launch Options to remove"
fi

echo ""
echo "=== Uninstall complete ==="
echo ""
echo "Note: vibration_fix.dylib and config.txt were NOT deleted."
echo "To fully remove, delete this directory."
