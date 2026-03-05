# Fishing Planet Vibration Fix — Project Guide

## What this is
A macOS mod for Fishing Planet (Steam) that enables Xbox controller vibration. Unity disables vibration on macOS; this mod hooks IL2CPP runtime to intercept vibration commands and outputs them via Steam Input API or IOKit HID. Additionally, it hooks fishing game methods via ARM64 inline hooks to provide real-time fight vibration from rod strain, line tension, and fish force.

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
│   ├── vibfix.h             # Shared header: config struct, IL2CPP types, externs
│   ├── vibfix_config.c      # Config file parsing (config.txt → VibConfig)
│   ├── vibfix_hooks.c       # IOCTL hooks + inline fishing hooks (ARM64 code patching)
│   ├── vibfix_output.m      # Rumble output (Steam/HID), fight vibration thread
│   ├── vibration_fix.m      # Init: IL2CPP API resolution, Steam Input, HID thread
│   ├── VibFixApp.m          # GUI app source (Objective-C, AppKit)
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

### Vibration pipelines

There are two independent vibration paths:

**1. IOCTL pipeline** (bite/reel events from Unity's native input system):
```
Unity IOCTL (RMBL command) → hook_ioctl → sendRumble → classify (BITE/REEL/HIGH) → apply config → outputRumble
```

**2. Fishing hooks pipeline** (real-time fight data from IL2CPP game methods):
```
Inline ARM64 hooks → read FishForce/RodForce/LineTension/HapticPulse
  → fight_vibration_thread (20Hz) → mix 3 continuous sources → outputRumble
  → hook_TriggerHapticPulse → pulse vibration + call original (triggers IOCTL BITE)
```

### Event classification (IOCTL path)
- **BITE**: `lowFreq > 0.30` — fish strikes the hook (triggered by TriggerHapticPulseOnRod original)
- **REEL**: `0.001 < lowFreq <= 0.30` — reeling/pulling fish in (normalized: `str = lowFreq / 0.30f`)
- **HIGH**: `lowFreq < 0.001 && highFreq >= 0.001` — high-freq only (unknown, logged for analysis)

### Fight vibration sources (inline hooks path)

| Source | Hook target | Config prefix | Character |
|--------|------------|---------------|-----------|
| **FishForce** | `IFishController.get_CurrentForce` | `fish_` | Constant per fish (12–66+), normalize /40 |
| **RodForce** | `Rod1stBehaviour.GetRodForce` | `rod_` | Delta-based: vibrate on increasing load only |
| **LineTension** | `Line1stBehaviour.GetLineTensionFactor` | `tension_` | Raw value (0–1 useful range) |
| **HapticPulse** | `TriggerHapticPulseOnRod` | `pulse_` | Short burst on game events + calls original |

Fight thread activates when ANY source shows activity:
- `FishForce >= 0.5` (fish hooked)
- `|RodForce| >= 1.0` (rod under load, catches pre-hook pulls)
- `LineTension >= 0.03` (line tension rising)

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
- `VibFix.app`: Cocoa, QuartzCore, IOKit
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

## IL2CPP hooking

### WORKS: icall hooks (api_resolve_icall + api_add_internal_call)
- Replaces function pointers in Unity's internal call registry
- Proven: IOCTL hook, SupportsVibration hook — both work reliably
- These intercept calls from managed C# code to native Unity C++ code

### WORKS: ARM64 inline hooks (mach_vm_remap trampoline)
- Allocates a trampoline pool via `mach_vm_allocate`
- For each hook: copies original instruction to trampoline, patches first 16 bytes of target with `LDR X16, [PC+8]; BR X16; <address>` pointing to our hook
- Trampoline contains: original instruction + branch back to target+4
- Uses `mach_vm_remap` to remap trampoline page as RX (bypasses Hardened Runtime)
- Used for: `GetLineTensionFactor`, `get_CurrentForce`, `GetRodForce`, `TriggerHapticPulseOnRod`
- **Critical**: target functions must be > 16 bytes apart, otherwise patch corrupts neighbor

### WORKS: IL2CPP readiness validation
- `resolve_il2cpp_api()` iterates ALL assemblies checking `api_image_get_class_count > 0`
- Prevents crash when IL2CPP symbols resolve but metadata tables aren't populated yet
- Earlier approach (checking single assembly) caused TIMEOUT — the test class wasn't in `assemblies[0]`

### DOES NOT WORK: MethodInfo patching (patch_method_pointer)
- IL2CPP compiles ALL intra-assembly C# calls as direct native function calls
- The compiled code never reads MethodInfo->methodPointer at call time
- Result: changes metadata but zero calls are intercepted

### DOES NOT WORK: __DATA segment scanning (scan_image_data)
- Replaces metadata/reflection entries, NOT call-site targets
- Result: shows "cache=1" but calls still go to original function

### Key findings from class scanning
- `VibrateJoystick` and `VibrateJoystickIfLineIsNotTensioned` methods were REMOVED in a game update
- Game uses `TriggerHapticPulseOnRod` for bite events (this triggers IOCTL RMBL internally)
- IOCTL RMBL only carries zero values unless TriggerHapticPulseOnRod original is called
- FishForce can arrive 1–6 seconds after the initial bite pulse, or not at all for escaped fish

### IOCTL command types observed
- `RMBL` (0x524D424C) — rumble command, 8 bytes: lowFreq(float) + highFreq(float)
- `QENB` (0x51454E42) — query enable, 1 byte
- `SYNC` (0x53594E43) — sync device state, 0 bytes
- `ENBL` (0x454E424C) — enable device, 0 bytes
- `DSBL` (0x4453424C) — disable device, 0 bytes
- `RSET` (0x52534554) — reset device, 0 bytes
- `QRIB` (0x51524942) — query rumble info/capability, 1 byte

## Important notes

- Steam overwrites `localconfig.vdf` on exit — must close Steam before modifying
- `VIBFIX_SKIP_STEAM_CHECK=1` env var — used by GUI app to skip Steam running check in install.sh
- IOKit HID: Xbox Bluetooth rumble = Report ID 0x03, 9-byte report
- Steam Input: uses `SteamAPI_ISteamInput_TriggerVibrationExtended` when available (4-motor)
- FMOD hooks were attempted but removed — setVolume/setFrequency are only 8 bytes apart, 16-byte inline hook patch corrupts the neighbor function (SIGILL crash)
- TriggerHapticPulse hook MUST call the original function — it's the source of IOCTL RMBL BITE events
- Haptic pulse auto-stops after 200ms via dispatch_after (prevents infinite vibration on trash catches)
