// vibfix_output.m — Steam Input, IOKit HID, rumble output, test vibration

#include "vibfix.h"

// ============ Steam Input API ============

SteamInput_fn api_SteamInput = NULL;
SteamInputInit_fn api_SteamInputInit = NULL;
SteamInputRunFrame_fn api_SteamInputRunFrame = NULL;
GetConnectedControllers_fn api_GetControllers = NULL;
TriggerVibration_fn api_TriggerVibration = NULL;
TriggerVibrationExtended_fn api_TriggerVibrationExt = NULL;
ISteamInput g_steamInput = NULL;
InputHandle_t g_controllerHandle = 0;
int g_steamReady = 0;  // 0=not tried, 1=ready, -1=failed

static float g_curLow = -1.0f;
static float g_curHigh = -1.0f;

// Steam diagnostic helpers
typedef int32_t HSteamPipe;
typedef int32_t HSteamUser;
typedef HSteamPipe (*GetHSteamPipe_fn)(void);
typedef HSteamUser (*GetHSteamUser_fn)(void);
static GetHSteamPipe_fn api_GetHSteamPipe = NULL;
static GetHSteamUser_fn api_GetHSteamUser = NULL;

void initSteamInput(void) {
    if (g_steamReady != 0) return;

    void *steam = dlopen("libsteam_api.dylib", RTLD_NOLOAD | RTLD_NOW);
    if (!steam) {
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char *name = _dyld_get_image_name(i);
            if (name && strstr(name, "libsteam_api")) {
                steam = dlopen(name, RTLD_NOLOAD | RTLD_NOW);
                if (steam) break;
            }
        }
    }
    if (!steam) {
        viblog("Steam: libsteam_api.dylib not found");
        g_steamReady = -1;
        return;
    }

    // Get diagnostic functions
    if (!api_GetHSteamPipe)
        api_GetHSteamPipe = (GetHSteamPipe_fn)dlsym(steam, "SteamAPI_GetHSteamPipe");
    if (!api_GetHSteamUser)
        api_GetHSteamUser = (GetHSteamUser_fn)dlsym(steam, "SteamAPI_GetHSteamUser");

    api_SteamInput = (SteamInput_fn)dlsym(steam, "SteamAPI_SteamInput_v006");
    api_SteamInputInit = (SteamInputInit_fn)dlsym(steam, "SteamAPI_ISteamInput_Init");
    api_SteamInputRunFrame = (SteamInputRunFrame_fn)dlsym(steam, "SteamAPI_ISteamInput_RunFrame");
    api_GetControllers = (GetConnectedControllers_fn)dlsym(steam, "SteamAPI_ISteamInput_GetConnectedControllers");
    api_TriggerVibration = (TriggerVibration_fn)dlsym(steam, "SteamAPI_ISteamInput_TriggerVibration");
    api_TriggerVibrationExt = (TriggerVibrationExtended_fn)dlsym(steam, "SteamAPI_ISteamInput_TriggerVibrationExtended");

    if (!api_SteamInput || !api_GetControllers || !api_TriggerVibration) {
        viblog("Steam: missing required API functions");
        g_steamReady = -1;
        return;
    }

    // Diagnostic: check if Steam API is initialized
    int32_t pipe = api_GetHSteamPipe ? api_GetHSteamPipe() : -1;
    int32_t user = api_GetHSteamUser ? api_GetHSteamUser() : -1;
    viblog("Steam: pipe=%d user=%d", pipe, user);

    if (pipe == 0 || user == 0) {
        viblog("Steam: API not initialized yet — will retry");
        return;
    }

    g_steamInput = api_SteamInput();
    if (!g_steamInput) {
        viblog("Steam: SteamInput() returned NULL (pipe=%d user=%d) — will retry", pipe, user);
        return;
    }

    if (api_SteamInputInit) {
        bool ok = api_SteamInputInit(g_steamInput, true);
        viblog("Steam: Init returned %d", ok);
    }
    if (api_SteamInputRunFrame) {
        api_SteamInputRunFrame(g_steamInput);
    }

    InputHandle_t handles[16] = {0};
    int n = api_GetControllers(g_steamInput, handles);
    viblog("Steam: %d controllers connected", n);

    if (n > 0) {
        g_controllerHandle = handles[0];
        g_steamReady = 1;
        viblog("Steam: using controller 0x%llx", (unsigned long long)g_controllerHandle);
    } else {
        viblog("Steam: no controllers — will retry");
    }
}

// ============ IOKit HID Fallback ============

static IOHIDDeviceRef g_xbox_hid = NULL;
int g_hid_ready = 0;

// Xbox controller Product IDs (all use Vendor ID 0x045E)
static const int g_xbox_pids[] = {
    0x0B13, // Xbox Series X|S
    0x0B20, // Xbox Series X|S (newer fw)
    0x0B21, // Xbox Adaptive Controller
    0x0B22, // Xbox Elite Series 2 (newer fw)
    0x02E0, // Xbox One S
    0x02FD, // Xbox One S (newer fw)
    0x0B05, // Xbox Elite Series 2
    0x0B12, // Xbox Core (2021+)
    0
};

static int is_xbox_pid(int pid) {
    for (int i = 0; g_xbox_pids[i]; i++)
        if (g_xbox_pids[i] == pid) return 1;
    return 0;
}

static void xbox_hid_matched(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (g_hid_ready) return;

    CFNumberRef pidRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
    int32_t pid = 0;
    if (pidRef) CFNumberGetValue(pidRef, kCFNumberSInt32Type, &pid);

    CFStringRef nameRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
    char name[128] = "unknown";
    if (nameRef) CFStringGetCString(nameRef, name, sizeof(name), kCFStringEncodingUTF8);

    viblog("HID: device matched VID=045E PID=%04X '%s'", pid, name);

    if (is_xbox_pid(pid)) {
        g_xbox_hid = device;
        CFRetain(device);
        g_hid_ready = 1;
        viblog("HID: Xbox controller ready (PID=0x%04X)", pid);
    }
}

static void xbox_hid_removed(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (device == g_xbox_hid) {
        viblog("HID: Xbox controller disconnected");
        g_hid_ready = 0;
        CFRelease(g_xbox_hid);
        g_xbox_hid = NULL;
    }
}

void *hid_thread(void *arg) {
    viblog("HID: starting fallback controller search...");
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!mgr) { viblog("HID: IOHIDManagerCreate failed"); return NULL; }

    int vid = 0x045E;
    CFNumberRef vidNum = CFNumberCreate(NULL, kCFNumberIntType, &vid);
    CFStringRef keys[] = { CFSTR(kIOHIDVendorIDKey) };
    CFTypeRef vals[] = { vidNum };
    CFDictionaryRef match = CFDictionaryCreate(NULL, (const void **)keys, (const void **)vals,
                                                1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(mgr, match);
    CFRelease(match);
    CFRelease(vidNum);

    IOHIDManagerRegisterDeviceMatchingCallback(mgr, xbox_hid_matched, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(mgr, xbox_hid_removed, NULL);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);

    CFRunLoopRun();
    return NULL;
}

void send_hid_rumble(uint8_t lt, uint8_t rt, uint8_t left, uint8_t right) {
    if (!g_hid_ready || !g_xbox_hid) return;
    // Xbox One Bluetooth HID rumble report: ID=0x03, 9 bytes
    uint8_t report[9] = {0x03, 0x0F, lt, rt, left, right, 0xFF, 0x00, 0xEB};
    IOReturn ret = IOHIDDeviceSetReport(g_xbox_hid, kIOHIDReportTypeOutput, 0x03, report, sizeof(report));
    if (ret != kIOReturnSuccess) {
        static int errcnt = 0;
        if (++errcnt <= 5) viblog("HID: SetReport error 0x%x", ret);
    }
}

// ============ Test Vibration ============

void do_test_vibration(void) {
    if (!g_cfg.test_on_start) return;
    viblog("Test vibration...");

    uint8_t tL  = (uint8_t)(g_cfg.bite_left * 0.6f * 100.0f);
    uint8_t tR  = (uint8_t)(g_cfg.bite_right * 0.6f * 100.0f);
    uint8_t tLT = (uint8_t)(g_cfg.bite_trigger_left * 0.6f * 100.0f);
    uint8_t tRT = (uint8_t)(g_cfg.bite_trigger_right * 0.6f * 100.0f);

    if (g_steamReady == 1) {
        unsigned short sL = tL * 655, sR = tR * 655, sLT = tLT * 655, sRT = tRT * 655;
        if (api_TriggerVibrationExt)
            api_TriggerVibrationExt(g_steamInput, g_controllerHandle, sL, sR, sLT, sRT);
        else
            api_TriggerVibration(g_steamInput, g_controllerHandle, sL, sR);
        usleep(150000);
        if (api_TriggerVibrationExt)
            api_TriggerVibrationExt(g_steamInput, g_controllerHandle, 0, 0, 0, 0);
        else
            api_TriggerVibration(g_steamInput, g_controllerHandle, 0, 0);
        usleep(80000);
        unsigned short s2L = (unsigned short)(sL * g_cfg.bite_double_tap_strength);
        unsigned short s2R = (unsigned short)(sR * g_cfg.bite_double_tap_strength);
        if (api_TriggerVibrationExt)
            api_TriggerVibrationExt(g_steamInput, g_controllerHandle, s2L, s2R, sLT, sRT);
        else
            api_TriggerVibration(g_steamInput, g_controllerHandle, s2L, s2R);
        usleep(200000);
        if (api_TriggerVibrationExt)
            api_TriggerVibrationExt(g_steamInput, g_controllerHandle, 0, 0, 0, 0);
        else
            api_TriggerVibration(g_steamInput, g_controllerHandle, 0, 0);
        viblog("Test done (Steam Input)");
    } else if (g_hid_ready) {
        send_hid_rumble(tLT, tRT, tL, tR);
        usleep(150000);
        send_hid_rumble(0, 0, 0, 0);
        usleep(80000);
        uint8_t t2L = (uint8_t)(tL * g_cfg.bite_double_tap_strength);
        uint8_t t2R = (uint8_t)(tR * g_cfg.bite_double_tap_strength);
        send_hid_rumble(tLT, tRT, t2L, t2R);
        usleep(200000);
        send_hid_rumble(0, 0, 0, 0);
        viblog("Test done (HID fallback)");
    } else {
        viblog("Test: no output available (Steam=%d HID=%d)", g_steamReady, g_hid_ready);
    }
}

// ============ Rumble Output (Steam or HID) ============

void outputRumble(uint8_t left, uint8_t right, uint8_t lt, uint8_t rt) {
    if (g_shutting_down) return;
    if (g_steamReady == 1 && g_controllerHandle != 0) {
        unsigned short sL = left * 655, sR = right * 655;
        unsigned short sLT = lt * 655, sRT = rt * 655;
        if (api_TriggerVibrationExt)
            api_TriggerVibrationExt(g_steamInput, g_controllerHandle, sL, sR, sLT, sRT);
        else
            api_TriggerVibration(g_steamInput, g_controllerHandle, sL, sR);
    } else if (g_hid_ready) {
        send_hid_rumble(lt, rt, left, right);
    }
}

// ============ Rumble Dispatch ============

void sendRumble(float lowFreq, float highFreq) {
    if (lowFreq < 0) lowFreq = 0; if (lowFreq > 1) lowFreq = 1;
    if (highFreq < 0) highFreq = 0; if (highFreq > 1) highFreq = 1;
    if (lowFreq == g_curLow && highFreq == g_curHigh) {
        if (g_cfg.verbose_log) {
            static int dup_count = 0;
            dup_count++;
            if (dup_count <= 10 || dup_count % 50 == 0)
                viblog("  [dup #%d] same value skipped (%.4f/%.4f)", dup_count, lowFreq, highFreq);
        }
        return;
    }
    g_curLow = lowFreq; g_curHigh = highFreq;

    // Try to init output if not ready
    if (g_steamReady <= 0 && !g_hid_ready) {
        initSteamInput();
        if (g_steamReady != 1 && !g_hid_ready) return;
    }

    // Steam: refresh controller handle if needed
    if (g_steamReady == 1 && g_controllerHandle == 0 && api_GetControllers && g_steamInput) {
        if (api_SteamInputRunFrame) api_SteamInputRunFrame(g_steamInput);
        InputHandle_t handles[16] = {0};
        int n = api_GetControllers(g_steamInput, handles);
        if (n > 0) {
            g_controllerHandle = handles[0];
            viblog("Steam: controller found on retry: 0x%llx", (unsigned long long)g_controllerHandle);
        }
    }

    // Check we have at least one output
    int have_steam = (g_steamReady == 1 && g_controllerHandle != 0);
    int have_hid = g_hid_ready;
    if (!have_steam && !have_hid) return;

    uint8_t mL = 0, mR = 0, mLT = 0, mRT = 0;
    const char *event = "unknown";

    if (lowFreq < 0.001f && highFreq < 0.001f) {
        event = "stop";
    } else if (lowFreq > 0.30f) {
        float str = lowFreq;
        mL  = (uint8_t)(str * g_cfg.bite_left * 100.0f);
        mR  = (uint8_t)(str * g_cfg.bite_right * 100.0f);
        mLT = (uint8_t)(str * g_cfg.bite_trigger_left * 100.0f);
        mRT = (uint8_t)(str * g_cfg.bite_trigger_right * 100.0f);
        event = "BITE";

        if (g_cfg.bite_double_tap) {
            float dbl = g_cfg.bite_double_tap_strength;
            uint8_t d2L = (uint8_t)(mL * dbl);
            uint8_t d2R = (uint8_t)(mR * dbl);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC),
                           dispatch_get_main_queue(), ^{
                outputRumble(0, 0, 0, 0);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC),
                               dispatch_get_main_queue(), ^{
                    if (g_curLow < 0.1f) return;
                    viblog("  double-tap: L=%u R=%u LT=%u RT=%u", d2L, d2R, mLT, mRT);
                    outputRumble(d2L, d2R, mLT, mRT);
                });
            });
        }
    } else if (lowFreq < 0.001f && highFreq >= 0.001f) {
        // HIGH-FREQ ONLY — unknown event, log for analysis
        float str = highFreq;
        mL  = (uint8_t)(str * g_cfg.reel_left * 100.0f);
        mR  = (uint8_t)(str * g_cfg.reel_right * 100.0f);
        mLT = (uint8_t)(str * g_cfg.reel_trigger_left * 100.0f);
        mRT = (uint8_t)(str * g_cfg.reel_trigger_right * 100.0f);
        event = "HIGH";
    } else {
        // SLACK — line slack / провисание лески
        // normalize lowFreq from [0, 0.30] to [0, 1.0]
        float str = lowFreq / 0.30f;
        if (str > 1.0f) str = 1.0f;
        mL  = (uint8_t)(str * g_cfg.reel_left * 100.0f);
        mR  = (uint8_t)(str * g_cfg.reel_right * 100.0f);
        mLT = (uint8_t)(str * g_cfg.reel_trigger_left * 100.0f);
        mRT = (uint8_t)(str * g_cfg.reel_trigger_right * 100.0f);
        event = "SLACK";
    }

    outputRumble(mL, mR, mLT, mRT);

    const char *via = have_steam ? "Steam" : "HID";
    static int n = 0;
    n++;
    if (g_cfg.verbose_log || n <= 30 || n % 100 == 0)
        viblog("rumble #%d [%s via %s]: L=%u R=%u LT=%u RT=%u (src=%.4f/%.4f)",
               n, event, via, mL, mR, mLT, mRT, lowFreq, highFreq);
}

// ============ Fight Vibration Thread ============
// Polls fishing data at 20Hz, mixes 3 continuous sources (fish/rod/tension)

#include <math.h>

void *fight_vibration_thread(void *arg) {
    viblog("[FIGHT] vibration thread started");
    uint32_t last_tick = 0;
    int stale_count = 0;
    int was_fighting = 0;
    float prev_rod_abs = 0.0f;  // previous |rod| for delta calculation
    float smooth_tension = 0.0f;  // EMA-smoothed line tension
    int idle_zero_count = 0;      // counter for repeated zero sends when idle

    while (!g_shutting_down) {
        usleep(50000);  // 50ms = 20Hz
        if (g_shutting_down) break;

        // Smooth line tension with asymmetric EMA (always update, even when idle):
        // Fast rise (catch spikes), slow decay (bridge gaps in flickering data)
        float raw_tension = g_line_tension;
        if (raw_tension > smooth_tension)
            smooth_tension = smooth_tension * 0.5f + raw_tension * 0.5f;   // fast rise
        else
            smooth_tension = smooth_tension * 0.85f + raw_tension * 0.15f; // slow decay
        float tension = smooth_tension;

        // Game disabled vibration (e.g. boat mode DSBL command)
        if (g_vibration_disabled) {
            if (was_fighting) {
                outputRumble(0, 0, 0, 0);
                was_fighting = 0;
                smooth_tension = 0.0f;
                prev_rod_abs = 0.0f;
                viblog("[FIGHT] disabled by game (DSBL), stopping vibration");
            }
            continue;
        }

        float fish = g_fish_force;
        float rod_abs = fabsf(g_rod_force);

        // Activate when any source shows significant activity:
        // - FishForce >= 0.5 (fish hooked, normal fight)
        // - |RodForce| >= 1.0 (rod being pulled — fish may not be "hooked" yet)
        // - LineTension >= 0.15 (real fight tension; idle with heavy bait is ~0.04)
        // - Reeling (g_reel_speed > 0 means IsReeling flag is set by game)
        int active = (fish >= 0.5f) || (rod_abs >= 1.0f) || (tension >= 0.15f)
                   || (g_reel_speed > 0.0f);
        if (!active) {
            if (was_fighting) {
                outputRumble(0, 0, 0, 0);
                was_fighting = 0;
                prev_rod_abs = 0.0f;
                viblog("[FIGHT] activity stopped, stopping vibration");
                idle_zero_count = 0;
            }
            // Re-send zero a few times after stopping to handle BT packet loss
            if (idle_zero_count < 10) {
                idle_zero_count++;
                if (idle_zero_count % 5 == 0)
                    outputRumble(0, 0, 0, 0);
            }
            stale_count = 0;
            continue;
        }
        idle_zero_count = 0;
        if (!g_steamReady && !g_hid_ready) continue;

        // Detect stale fish force: if get_CurrentForce stopped being called,
        // the fish_force value is stale — zero it out
        uint32_t cur_tick = g_fish_force_tick;
        if (cur_tick == last_tick) {
            stale_count++;
            if (stale_count > 10 && g_fish_force > 0.0f) {  // 500ms no FishForce updates
                g_fish_force = 0;
                fish = 0;
            }
        } else {
            stale_count = 0;
            last_tick = cur_tick;
        }

        was_fighting = 1;

        // --- Normalize each source to 0.0–1.0 ---

        // Fish Force: constant per fish, normalize to 0–1
        float fish_str = fish / 40.0f;
        if (fish_str > 1.0f) fish_str = 1.0f;

        // Rod Force delta: vibrate only when load is INCREASING (rod bending more)
        // Steady or decreasing load → no rod vibration
        float cur_rod_abs = fabsf(g_rod_force);
        float rod_delta = cur_rod_abs - prev_rod_abs;
        prev_rod_abs = cur_rod_abs;
        float rod_str = 0.0f;
        if (rod_delta > 0.0f) {
            // Typical delta per 50ms tick: 0.5–5 (normal), 5–15 (spike)
            rod_str = rod_delta / 10.0f;
            if (rod_str > 1.0f) rod_str = 1.0f;
        }

        // Line Tension: deadzone 0.1, use smoothed value
        float tens_str = tension - 0.1f;
        if (tens_str < 0.0f) tens_str = 0.0f;
        if (tens_str > 1.0f) tens_str = 1.0f;

        // Suppress tension during cast/retrieve (no fish, low rod load)
        if (fish < 0.5f && cur_rod_abs < 5.0f)
            tens_str *= 0.1f;

        // Reel: pulsing tuk-tuk when applied force near maximum (~40+)
        // This mimics the drag ratchet clicking when reel is at max load.
        // Pulse pattern: 1 tick ON, 2 ticks OFF = ~6.7Hz at 20Hz loop
        static int reel_pulse_tick = 0;
        float reel_str = 0.0f;
        if (g_reel_speed > 0.0f && g_reel_force >= 40.0f) {
            reel_pulse_tick++;
            if (reel_pulse_tick % 3 == 0)
                reel_str = 1.0f;
        } else {
            reel_pulse_tick = 0;
        }

        // Mix: sum each motor channel independently, clamp to 255
        int mL  = (int)(fish_str * g_cfg.fish_left * 255)
                + (int)(rod_str  * g_cfg.rod_left * 255)
                + (int)(tens_str * g_cfg.tension_left * 255)
                + (int)(reel_str * g_cfg.reel_left * 255);
        int mR  = (int)(fish_str * g_cfg.fish_right * 255)
                + (int)(rod_str  * g_cfg.rod_right * 255)
                + (int)(tens_str * g_cfg.tension_right * 255)
                + (int)(reel_str * g_cfg.reel_right * 255);
        int mLT = (int)(fish_str * g_cfg.fish_trigger_left * 255)
                + (int)(rod_str  * g_cfg.rod_trigger_left * 255)
                + (int)(tens_str * g_cfg.tension_trigger_left * 255)
                + (int)(reel_str * g_cfg.reel_trigger_left * 255);
        int mRT = (int)(fish_str * g_cfg.fish_trigger_right * 255)
                + (int)(rod_str  * g_cfg.rod_trigger_right * 255)
                + (int)(tens_str * g_cfg.tension_trigger_right * 255)
                + (int)(reel_str * g_cfg.reel_trigger_right * 255);

        if (mL > 255) mL = 255; if (mR > 255) mR = 255;
        if (mLT > 255) mLT = 255; if (mRT > 255) mRT = 255;

        static int fc = 0;
        fc++;
        if (fc <= 20 || fc % 100 == 0)
            viblog("[FIGHT] #%d fish=%.1f rod_d=%.2f tens=%.2f reel=%.2f → L=%d R=%d LT=%d RT=%d",
                   fc, fish_str, rod_str, tens_str, reel_str, mL, mR, mLT, mRT);

        outputRumble((uint8_t)mL, (uint8_t)mR, (uint8_t)mLT, (uint8_t)mRT);
    }
    viblog("[FIGHT] thread exiting (shutdown)");
    return NULL;
}
