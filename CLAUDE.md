# Fishing Planet Vibration Fix — Project Guide

## What this is
A macOS mod for Fishing Planet (Steam) that enables Xbox controller vibration. Unity disables vibration on macOS; this mod hooks IL2CPP runtime to intercept vibration commands and outputs them via Steam Input API or IOKit HID.

## Project structure

```
/
├── VibFix.app/              # GUI app (pre-built, user-facing)
├── README.md                # Documentation (EN + RU)
├── config.txt               # User vibration settings
├── CLAUDE.md                # This file
├── Makefile                 # Build rules
├── build.sh                 # Build convenience script
├── scripts/
│   ├── install.sh           # CLI installer (auto-configures Steam)
│   └── uninstall.sh         # CLI uninstaller
├── src/
│   ├── VibFixApp.m          # GUI app source (Objective-C, AppKit)
│   ├── vibration_fix.m      # Core dylib source (IL2CPP hooks)
│   ├── launch_wrapper.c     # Steam Launch Options wrapper (C)
│   └── launcher.c           # Legacy launcher (pre-v9.0)
├── build/
│   ├── launch               # Pre-built wrapper binary
│   └── vibration_fix.dylib  # Pre-built dylib
└── assets/
    ├── back.png             # Banner image for GUI
    └── AppIcon.icns         # App icon (.icns)
```

## Architecture

### Injection chain
```
Steam Launch Options → build/launch (wrapper) → sets DYLD_INSERT_LIBRARIES → game loads build/vibration_fix.dylib
```

### Vibration pipeline
```
Unity IOCTL (RMBL command) → hook_ioctl → sendRumble → classify event (BITE/REEL/HIGH) → apply config → outputRumble → Steam Input API or IOKit HID
```

### Event classification
- **BITE**: `lowFreq > 0.30` — fish strikes the hook
- **REEL**: `0.001 < lowFreq <= 0.30` — reeling/pulling fish in (normalized: `str = lowFreq / 0.30f`)
- **HIGH**: `lowFreq < 0.001 && highFreq >= 0.001` — high-freq only (unknown, logged for analysis)

## Build

```bash
make all                        # Build everything
make VibFix.app                 # Build GUI app only
make build/vibration_fix.dylib  # Build dylib only
make build/launch               # Build launch wrapper only
```

Requires: clang, Xcode Command Line Tools, macOS 13+ ARM64.

Frameworks used:
- `vibration_fix.dylib`: Foundation, GameController, IOKit
- `VibFix.app`: Cocoa, QuartzCore
- `launch`: none (pure C)

## Coding conventions

- **Language**: Objective-C for dylib and GUI app, C for launch wrapper
- **No Xcode project** — everything builds from Makefile with clang
- **GUI**: Programmatic AppKit layout (no XIBs/storyboards), `FlippedView` for top-down coordinate system
- **Localization**: `g_lang` global (0=EN, 1=RU), `L()` returns dictionary, `S(key)` macro for lookup
- **Config format**: `key = value` in config.txt, values are integers 0-100 or `true`/`false`
- **Logging**: all output goes to `vibfix.log` (dylib) or `launch.log` (wrapper), both in project root
- **Path resolution**: dylib finds config.txt relative to itself, falls back to parent dir (for build/ layout)

## Steam integration

- Steam config: `~/Library/Application Support/Steam/userdata/<id>/config/localconfig.vdf`
- App ID: `380600` (Fishing Planet)
- scripts/install.sh parses VDF with Python to set LaunchOptions
- Steam passes `.app` bundle path in `%command%` — wrapper must resolve to `Contents/MacOS/<binary>`
- Must preserve existing `DYLD_INSERT_LIBRARIES` (Steam overlay)

## Important notes

- Steam overwrites `localconfig.vdf` on exit — must close Steam before modifying
- `VIBFIX_SKIP_STEAM_CHECK=1` env var — used by GUI app to skip Steam running check in install.sh
- IOKit HID: Xbox Bluetooth rumble = Report ID 0x03, 9-byte report
- Steam Input: uses `SteamAPI_ISteamInput_TriggerVibrationExtended` when available (4-motor)
