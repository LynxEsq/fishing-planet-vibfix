#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ID="380600"
STEAM_DIR="$HOME/Library/Application Support/Steam"
USERDATA_DIR="$STEAM_DIR/userdata"
GAME_APP="$STEAM_DIR/steamapps/common/Fishing Planet/FishingPlanet.app"
GAME_MACOS="$GAME_APP/Contents/MacOS"

echo "=== Fishing Planet Vibration Fix — Installer ==="
echo ""

# ── Step 1: Check game is installed ──
if [ ! -d "$GAME_APP" ]; then
    echo "ERROR: Fishing Planet not found at:"
    echo "  $GAME_APP"
    echo ""
    echo "Install the game via Steam first."
    exit 1
fi
echo "[OK] Game found"

# ── Step 2: Build binaries if needed ──
LAUNCH_BIN="$PROJECT_DIR/build/launch"
DYLIB="$PROJECT_DIR/build/vibration_fix.dylib"

if [ -f "$LAUNCH_BIN" ] && [ -f "$DYLIB" ]; then
    echo "[OK] Binaries found"
else
    echo "Building from source (requires Xcode Command Line Tools)..."
    make -C "$PROJECT_DIR" build/vibration_fix.dylib build/launch
    echo "[OK] Built successfully"
fi

# ── Step 3: Restore original game binary if old install method was used ──
REAL_BIN="$GAME_MACOS/FishingPlanet_real"
if [ -f "$REAL_BIN" ]; then
    echo "Restoring original game binary (removing old install method)..."
    mv "$REAL_BIN" "$GAME_MACOS/FishingPlanet"
    rm -f "$GAME_MACOS/.vibfix_dylib_path"
    echo "[OK] Original binary restored"
fi

# ── Step 4: Check Steam is closed ──
if [ "$VIBFIX_SKIP_STEAM_CHECK" != "1" ] && pgrep -fi "Steam" > /dev/null 2>&1; then
    echo ""
    echo "Steam is running. Please close Steam completely and re-run this script."
    echo "(Steam overwrites its config on exit, so it must be closed first.)"
    exit 1
fi
echo "[OK] Steam is not running"

# ── Step 5: Find localconfig.vdf ──
if [ ! -d "$USERDATA_DIR" ]; then
    echo "ERROR: Steam userdata not found at:"
    echo "  $USERDATA_DIR"
    exit 1
fi

CONFIGS=()
for user_dir in "$USERDATA_DIR"/*/; do
    vdf="$user_dir/config/localconfig.vdf"
    if [ -f "$vdf" ]; then
        # Only process configs that have Fishing Planet data
        if grep -q "\"$APP_ID\"" "$vdf" 2>/dev/null; then
            CONFIGS+=("$vdf")
        fi
    fi
done

if [ ${#CONFIGS[@]} -eq 0 ]; then
    echo "ERROR: No Steam config found with Fishing Planet data."
    echo "Launch Fishing Planet at least once from Steam, then re-run this script."
    exit 1
fi
echo "[OK] Found ${#CONFIGS[@]} Steam config(s) with Fishing Planet"

# ── Step 6: Set Launch Options via Python ──
python3 << PYEOF
import sys, os, shutil

app_id = "$APP_ID"
launch_path = "$LAUNCH_BIN"
vdf_files = """${CONFIGS[*]}""".strip().split("\n")

# VDF value: path %command% (no inner quotes — VDF doesn't support \" escaping,
# Steam corrupts the value on re-save if inner quotes are present)
vdf_value = launch_path + ' %command%'

for vdf_path in vdf_files:
    vdf_path = vdf_path.strip()
    if not vdf_path:
        continue
    print(f"  Config: {vdf_path}")

    # Backup original (once)
    backup = vdf_path + ".vibfix_backup"
    if not os.path.exists(backup):
        shutil.copy2(vdf_path, backup)
        print(f"  Backup saved: {backup}")

    with open(vdf_path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()

    # Find the "380600" { ... } section that contains "LastPlayed"
    target_open = -1   # line with {
    target_close = -1  # line with }
    i = 0
    while i < len(lines):
        stripped = lines[i].strip()
        # Match "380600" as a standalone key (no value on same line)
        if stripped == f'"{app_id}"':
            # Find the opening brace
            j = i + 1
            while j < len(lines) and lines[j].strip() == '':
                j += 1
            if j < len(lines) and lines[j].strip() == '{':
                # Scan section to check if it has "LastPlayed"
                k = j + 1
                depth = 1
                has_lastplayed = False
                while k < len(lines) and depth > 0:
                    s = lines[k].strip()
                    if s == '{':
                        depth += 1
                    elif s == '}':
                        depth -= 1
                    if '"LastPlayed"' in s or '"Playtime"' in s:
                        has_lastplayed = True
                    k += 1
                if has_lastplayed:
                    target_open = j
                    target_close = k - 1
                    break
        i += 1

    if target_open == -1:
        print(f"  WARNING: Fishing Planet app section not found, skipping")
        continue

    # Detect indentation from existing lines in the section
    indent = ''
    for j in range(target_open + 1, target_close):
        s = lines[j]
        if s.strip() and '"' in s:
            indent = s[:len(s) - len(s.lstrip())]
            break

    new_line = f'{indent}"LaunchOptions"\t\t"{vdf_value}"\n'

    # Remove orphaned lines from previous broken VDF escaping
    # (lines containing %command% that aren't LaunchOptions)
    orphan_lines = []
    for j in range(target_open + 1, target_close):
        s = lines[j].strip()
        if '%command%' in s and '"LaunchOptions"' not in s:
            orphan_lines.append(j)
    for j in reversed(orphan_lines):
        removed = lines.pop(j)
        target_close -= 1
        print(f"  Removed orphaned line: {removed.strip()}")

    # Find existing LaunchOptions in this section
    launch_line = -1
    for j in range(target_open + 1, target_close):
        if '"LaunchOptions"' in lines[j]:
            launch_line = j
            break

    if launch_line >= 0:
        lines[launch_line] = new_line
        print(f"  Updated LaunchOptions")
    else:
        lines.insert(target_close, new_line)
        print(f"  Added LaunchOptions")

    with open(vdf_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)

print("  Done!")
PYEOF

echo "[OK] Steam Launch Options configured"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Open Steam and click Play on Fishing Planet — that's it!"
echo ""
echo "  Test vibration on start = it works."
echo "  Edit config.txt to customize vibration strength."
echo "  Changes apply on next game restart."
echo ""
