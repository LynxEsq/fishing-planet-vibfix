// vibration_fix.dylib — enables Xbox controller vibration in Fishing Planet on macOS
//
// Hooks Unity's IL2CPP runtime via DYLD_INSERT_LIBRARIES to intercept vibration
// commands (IOCTL RMBL) and redirect them through Steam's Input API.
// Falls back to direct IOKit HID rumble if Steam Input is unavailable.

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDManager.h>
#import <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <pthread.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>

#define VERSION "8.0"

// Forward declarations
static void initControllerMonitoring(void);

// ============ Install Directory Detection ============

static char g_install_dir[1024] = "/tmp/vibration_fix";

static void find_install_dir(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "vibration_fix.dylib")) {
            strncpy(g_install_dir, name, sizeof(g_install_dir) - 1);
            char *last_slash = strrchr(g_install_dir, '/');
            if (last_slash) *last_slash = '\0';
            break;
        }
    }
}

// ============ Configuration ============

typedef struct {
    float bite_left;
    float bite_right;
    float bite_trigger_left;
    float bite_trigger_right;
    int   bite_double_tap;
    float bite_double_tap_strength;

    float reel_left;
    float reel_right;
    float reel_trigger_left;
    float reel_trigger_right;

    int   test_on_start;
} VibConfig;

static VibConfig g_cfg = {
    .bite_left = 1.0f,
    .bite_right = 0.5f,
    .bite_trigger_left = 0.4f,
    .bite_trigger_right = 0.5f,
    .bite_double_tap = 1,
    .bite_double_tap_strength = 0.75f,

    .reel_left = 0.45f,
    .reel_right = 1.0f,
    .reel_trigger_left = 0.3f,
    .reel_trigger_right = 0.5f,

    .test_on_start = 1,
};

static float clampf(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

static void load_config(void);  // defined after logging

// ============ Logging ============

static FILE *g_logfile = NULL;
static pthread_mutex_t g_logmutex = PTHREAD_MUTEX_INITIALIZER;

static void viblog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void viblog(const char *fmt, ...) {
    pthread_mutex_lock(&g_logmutex);
    if (!g_logfile) {
        char path[1100];
        snprintf(path, sizeof(path), "%s/vibfix.log", g_install_dir);
        g_logfile = fopen(path, "w");
        if (g_logfile) setbuf(g_logfile, NULL);
    }
    if (g_logfile) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        struct tm tm;
        localtime_r(&tv.tv_sec, &tm);
        fprintf(g_logfile, "[%02d:%02d:%02d.%03d] ",
                tm.tm_hour, tm.tm_min, tm.tm_sec, (int)(tv.tv_usec / 1000));
        va_list ap;
        va_start(ap, fmt);
        vfprintf(g_logfile, fmt, ap);
        fprintf(g_logfile, "\n");
        va_end(ap);
    }
    pthread_mutex_unlock(&g_logmutex);
}

// ============ Config Loading (needs viblog) ============

static void load_config(void) {
    char path[1100];
    snprintf(path, sizeof(path), "%s/config.txt", g_install_dir);

    FILE *f = fopen(path, "r");
    if (!f) {
        viblog("Config: %s not found, using defaults", path);
        return;
    }
    viblog("Config: loading %s", path);

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\0') continue;

        char key[64] = {0};
        char val[64] = {0};
        if (sscanf(p, "%63[^= ] = %63s", key, val) != 2) continue;

        int is_true = (strcmp(val, "true") == 0 || strcmp(val, "1") == 0 ||
                       strcmp(val, "yes") == 0);
        float fv = clampf(atof(val) / 100.0f);

        if (strcmp(key, "bite_left_motor") == 0)           g_cfg.bite_left = fv;
        else if (strcmp(key, "bite_right_motor") == 0)      g_cfg.bite_right = fv;
        else if (strcmp(key, "bite_left_trigger") == 0)     g_cfg.bite_trigger_left = fv;
        else if (strcmp(key, "bite_right_trigger") == 0)    g_cfg.bite_trigger_right = fv;
        else if (strcmp(key, "bite_double_tap") == 0)       g_cfg.bite_double_tap = is_true;
        else if (strcmp(key, "bite_double_tap_strength") == 0) g_cfg.bite_double_tap_strength = fv;
        else if (strcmp(key, "reel_left_motor") == 0)       g_cfg.reel_left = fv;
        else if (strcmp(key, "reel_right_motor") == 0)      g_cfg.reel_right = fv;
        else if (strcmp(key, "reel_left_trigger") == 0)     g_cfg.reel_trigger_left = fv;
        else if (strcmp(key, "reel_right_trigger") == 0)    g_cfg.reel_trigger_right = fv;
        else if (strcmp(key, "test_on_start") == 0)         g_cfg.test_on_start = is_true;
    }
    fclose(f);

    viblog("Config: bite L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%% dbl=%d dbl_str=%.0f%%",
           g_cfg.bite_left*100, g_cfg.bite_right*100,
           g_cfg.bite_trigger_left*100, g_cfg.bite_trigger_right*100,
           g_cfg.bite_double_tap, g_cfg.bite_double_tap_strength*100);
    viblog("Config: reel L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%%",
           g_cfg.reel_left*100, g_cfg.reel_right*100,
           g_cfg.reel_trigger_left*100, g_cfg.reel_trigger_right*100);
    viblog("Config: test_on_start=%d", g_cfg.test_on_start);
}

// ============ IL2CPP API typedefs ============

typedef void* Il2CppDomain;
typedef void* Il2CppAssembly;
typedef void* Il2CppImage;
typedef void* Il2CppClass;
typedef void* Il2CppMethodPointer;

typedef struct {
    Il2CppMethodPointer methodPointer;
} MethodInfo;

typedef Il2CppDomain (*il2cpp_domain_get_t)(void);
typedef Il2CppAssembly** (*il2cpp_domain_get_assemblies_t)(Il2CppDomain domain, size_t *count);
typedef Il2CppImage* (*il2cpp_assembly_get_image_t)(Il2CppAssembly *assembly);
typedef Il2CppClass* (*il2cpp_class_from_name_t)(Il2CppImage *image, const char *ns, const char *name);
typedef MethodInfo* (*il2cpp_class_get_method_from_name_t)(Il2CppClass *klass, const char *name, int argsCount);
typedef const MethodInfo* (*il2cpp_class_get_methods_t)(Il2CppClass *klass, void **iter);
typedef const char* (*il2cpp_method_get_name_t)(const MethodInfo *method);
typedef Il2CppMethodPointer (*il2cpp_resolve_icall_t)(const char *name);
typedef void (*il2cpp_add_internal_call_t)(const char *name, Il2CppMethodPointer method);

static il2cpp_domain_get_t api_domain_get = NULL;
static il2cpp_domain_get_assemblies_t api_domain_get_assemblies = NULL;
static il2cpp_assembly_get_image_t api_assembly_get_image = NULL;
static il2cpp_class_from_name_t api_class_from_name = NULL;
static il2cpp_class_get_method_from_name_t api_class_get_method_from_name = NULL;
static il2cpp_class_get_methods_t api_class_get_methods = NULL;
static il2cpp_method_get_name_t api_method_get_name = NULL;
static il2cpp_resolve_icall_t api_resolve_icall = NULL;
static il2cpp_add_internal_call_t api_add_internal_call = NULL;

// ============ Steam Input API ============

typedef void* ISteamInput;
typedef uint64_t InputHandle_t;

typedef ISteamInput (*SteamInput_fn)(void);
typedef bool (*SteamInputInit_fn)(ISteamInput self, bool bExplicitlyCallRunFrame);
typedef void (*SteamInputRunFrame_fn)(ISteamInput self);
typedef int (*GetConnectedControllers_fn)(ISteamInput self, InputHandle_t *handles);
typedef void (*TriggerVibration_fn)(ISteamInput self, InputHandle_t handle,
                                     unsigned short left, unsigned short right);
typedef void (*TriggerVibrationExtended_fn)(ISteamInput self, InputHandle_t handle,
                                            unsigned short left, unsigned short right,
                                            unsigned short leftTrigger, unsigned short rightTrigger);

static SteamInput_fn api_SteamInput = NULL;
static SteamInputInit_fn api_SteamInputInit = NULL;
static SteamInputRunFrame_fn api_SteamInputRunFrame = NULL;
static GetConnectedControllers_fn api_GetControllers = NULL;
static TriggerVibration_fn api_TriggerVibration = NULL;
static TriggerVibrationExtended_fn api_TriggerVibrationExt = NULL;
static ISteamInput g_steamInput = NULL;
static InputHandle_t g_controllerHandle = 0;
static float g_curLow = -1.0f;
static float g_curHigh = -1.0f;
static int g_steamReady = 0;  // 0=not tried, 1=ready, -1=failed

// Steam diagnostic helpers
typedef int32_t HSteamPipe;
typedef int32_t HSteamUser;
typedef HSteamPipe (*GetHSteamPipe_fn)(void);
typedef HSteamUser (*GetHSteamUser_fn)(void);
static GetHSteamPipe_fn api_GetHSteamPipe = NULL;
static GetHSteamUser_fn api_GetHSteamUser = NULL;

static void initSteamInput(void) {
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
static int g_hid_ready = 0;

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

static void *hid_thread(void *arg) {
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

static void send_hid_rumble(uint8_t lt, uint8_t rt, uint8_t left, uint8_t right) {
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

static void do_test_vibration(void) {
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

static void outputRumble(uint8_t left, uint8_t right, uint8_t lt, uint8_t rt) {
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

static void sendRumble(float lowFreq, float highFreq) {
    if (lowFreq < 0) lowFreq = 0; if (lowFreq > 1) lowFreq = 1;
    if (highFreq < 0) highFreq = 0; if (highFreq > 1) highFreq = 1;
    if (lowFreq == g_curLow && highFreq == g_curHigh) return;
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
        // BITE
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
    } else {
        // REEL
        float str = lowFreq;
        mL  = (uint8_t)(str * g_cfg.reel_left * 100.0f);
        mR  = (uint8_t)(str * g_cfg.reel_right * 100.0f);
        mLT = (uint8_t)(str * g_cfg.reel_trigger_left * 100.0f);
        mRT = (uint8_t)(str * g_cfg.reel_trigger_right * 100.0f);
        event = "REEL";
    }

    outputRumble(mL, mR, mLT, mRT);

    const char *via = have_steam ? "Steam" : "HID";
    static int n = 0;
    if (++n <= 30 || n % 100 == 0)
        viblog("rumble #%d [%s via %s]: L=%u R=%u LT=%u RT=%u (src=%.3f/%.3f)",
               n, event, via, mL, mR, mLT, mRT, lowFreq, highFreq);
}

// ============ Unity Hook Functions ============

#define RMBL_FOURCC 0x524D424C

static Il2CppMethodPointer orig_ioctl_native = NULL;
static Il2CppMethodPointer orig_ioctl = NULL;
typedef int64_t (*ioctl_fn)(int32_t deviceId, int32_t type, void *buffer, int32_t size);

static int hook_supports_vibration(void) {
    return 1;
}

static int64_t hook_ioctl(int32_t deviceId, int32_t type, void *buffer, int32_t size) {
    // Log ALL IOCTL types for debugging (first 10 of each type)
    static int ioctl_count = 0;
    if (++ioctl_count <= 10 || ioctl_count % 500 == 0) {
        char fourcc[5] = {0};
        fourcc[0] = (type >> 24) & 0xFF;
        fourcc[1] = (type >> 16) & 0xFF;
        fourcc[2] = (type >> 8) & 0xFF;
        fourcc[3] = type & 0xFF;
        viblog("IOCTL #%d: type=0x%08X '%s' dev=%d size=%d", ioctl_count, type, fourcc, deviceId, size);
    }

    if (type == RMBL_FOURCC && buffer) {
        float low = 0, high = 0;
        if (size >= 16) {
            low  = *(float *)((uint8_t *)buffer + 8);
            high = *(float *)((uint8_t *)buffer + 12);
        } else if (size >= 8) {
            uint32_t hdr = *(uint32_t *)buffer;
            if (hdr == RMBL_FOURCC) {
                low  = *(float *)((uint8_t *)buffer + 8);
                high = *(float *)((uint8_t *)buffer + 12);
            } else {
                low  = *(float *)((uint8_t *)buffer + 0);
                high = *(float *)((uint8_t *)buffer + 4);
            }
        }
        static int n = 0;
        if (++n <= 20 || n % 100 == 0)
            viblog("RMBL #%d: low=%.3f high=%.3f dev=%d", n, low, high, deviceId);
        sendRumble(low, high);
        return (int64_t)(size > 0 ? size : 16);
    }
    if (orig_ioctl_native) return ((ioctl_fn)orig_ioctl_native)(deviceId, type, buffer, size);
    if (orig_ioctl) return ((ioctl_fn)orig_ioctl)(deviceId, type, buffer, size);
    return -1;
}

// ============ IL2CPP Patching ============

static void *find_gameassembly_handle(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "GameAssembly")) {
            viblog("Found GameAssembly at image #%u: %s", i, name);
            void *handle = dlopen(name, RTLD_NOLOAD | RTLD_NOW);
            if (handle) {
                viblog("dlopen OK: handle=%p", handle);
                return handle;
            } else {
                viblog("dlopen failed: %s", dlerror());
            }
        }
    }
    return NULL;
}

static int resolve_il2cpp_api(void) {
    api_domain_get = (il2cpp_domain_get_t)dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    if (!api_domain_get) {
        void *ga = find_gameassembly_handle();
        if (!ga) return 0;
        api_domain_get = (il2cpp_domain_get_t)dlsym(ga, "il2cpp_domain_get");
        api_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(ga, "il2cpp_domain_get_assemblies");
        api_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(ga, "il2cpp_assembly_get_image");
        api_class_from_name = (il2cpp_class_from_name_t)dlsym(ga, "il2cpp_class_from_name");
        api_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(ga, "il2cpp_class_get_method_from_name");
        api_class_get_methods = (il2cpp_class_get_methods_t)dlsym(ga, "il2cpp_class_get_methods");
        api_method_get_name = (il2cpp_method_get_name_t)dlsym(ga, "il2cpp_method_get_name");
        api_resolve_icall = (il2cpp_resolve_icall_t)dlsym(ga, "il2cpp_resolve_icall");
        api_add_internal_call = (il2cpp_add_internal_call_t)dlsym(ga, "il2cpp_add_internal_call");
    }

    // RTLD_DEFAULT fallbacks
    if (!api_domain_get_assemblies) api_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    if (!api_assembly_get_image) api_assembly_get_image = (il2cpp_assembly_get_image_t)dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    if (!api_class_from_name) api_class_from_name = (il2cpp_class_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    if (!api_class_get_method_from_name) api_class_get_method_from_name = (il2cpp_class_get_method_from_name_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    if (!api_class_get_methods) api_class_get_methods = (il2cpp_class_get_methods_t)dlsym(RTLD_DEFAULT, "il2cpp_class_get_methods");
    if (!api_method_get_name) api_method_get_name = (il2cpp_method_get_name_t)dlsym(RTLD_DEFAULT, "il2cpp_method_get_name");
    if (!api_resolve_icall) api_resolve_icall = (il2cpp_resolve_icall_t)dlsym(RTLD_DEFAULT, "il2cpp_resolve_icall");
    if (!api_add_internal_call) api_add_internal_call = (il2cpp_add_internal_call_t)dlsym(RTLD_DEFAULT, "il2cpp_add_internal_call");

    return (api_domain_get && api_domain_get_assemblies && api_assembly_get_image &&
            api_class_from_name && api_class_get_method_from_name && api_resolve_icall) ? 1 : 0;
}

static Il2CppClass* find_class(const char *ns, const char *name) {
    Il2CppDomain *domain = api_domain_get();
    if (!domain) return NULL;

    size_t count = 0;
    Il2CppAssembly **assemblies = api_domain_get_assemblies(domain, &count);

    for (size_t i = 0; i < count; i++) {
        Il2CppImage *image = api_assembly_get_image(assemblies[i]);
        if (!image) continue;
        Il2CppClass *klass = api_class_from_name(image, ns, name);
        if (klass) return klass;
    }
    return NULL;
}

static void patch_method_pointer(MethodInfo *method, void *new_func, void **save_orig) {
    if (!method) return;
    if (save_orig) *save_orig = method->methodPointer;
    method->methodPointer = new_func;
}

// Scan __DATA for cached icall pointers and replace them
static int scan_image_data(const char *image_substr,
                           uintptr_t find_val, uintptr_t replace_val) {
    uint32_t image_count = _dyld_image_count();
    for (uint32_t i = 0; i < image_count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, image_substr)) continue;

        const struct mach_header_64 *mh =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        if (!mh || mh->magic != MH_MAGIC_64) continue;

        const uint8_t *lc_ptr = (const uint8_t *)(mh + 1);
        int total = 0;

        for (uint32_t j = 0; j < mh->ncmds; j++) {
            const struct load_command *lc = (const struct load_command *)lc_ptr;
            if (lc->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)lc_ptr;
                if (strcmp(seg->segname, "__DATA") == 0 || strcmp(seg->segname, "__DATA_DIRTY") == 0) {
                    uintptr_t *start = (uintptr_t *)(seg->vmaddr + slide);
                    size_t nwords = (size_t)seg->vmsize / sizeof(uintptr_t);
                    for (size_t k = 0; k < nwords; k++) {
                        if (start[k] == find_val) { start[k] = replace_val; total++; }
                    }
                }
            }
            lc_ptr += lc->cmdsize;
        }
        return total;
    }
    return 0;
}

static void install_hooks(void) {
    viblog("--- Installing hooks ---");

    // Hook SystemInfo.supportsVibration
    Il2CppClass *sysinfo = find_class("UnityEngine", "SystemInfo");
    if (sysinfo) {
        const char *names[] = {"get_supportsVibration", "SupportsVibration",
                               "get_SupportsVibration", "supportsVibration", NULL};
        for (int i = 0; names[i]; i++) {
            MethodInfo *m = api_class_get_method_from_name(sysinfo, names[i], 0);
            if (m) { patch_method_pointer(m, (void *)hook_supports_vibration, NULL); break; }
        }
    }

    // Overwrite icall map entries
    void *native_sv = NULL, *native_io = NULL;
    if (api_resolve_icall && api_add_internal_call) {
        const char *sv_names[] = {"UnityEngine.SystemInfo::get_supportsVibration",
                                   "UnityEngine.SystemInfo::SupportsVibration",
                                   "UnityEngine.SystemInfo::get_SupportsVibration", NULL};
        for (int i = 0; sv_names[i]; i++) {
            void *p = api_resolve_icall(sv_names[i]);
            if (p) {
                native_sv = p;
                api_add_internal_call(sv_names[i], (Il2CppMethodPointer)hook_supports_vibration);
                viblog("icall '%s' hooked", sv_names[i]);
            }
        }
        native_io = api_resolve_icall("UnityEngineInternal.Input.NativeInputSystem::IOCTL");
        if (native_io) {
            orig_ioctl_native = (Il2CppMethodPointer)native_io;
            api_add_internal_call("UnityEngineInternal.Input.NativeInputSystem::IOCTL",
                                  (Il2CppMethodPointer)hook_ioctl);
            viblog("icall IOCTL hooked (native=%p)", native_io);
        }
    }

    // Hook IOCTL via MethodInfo patch too
    Il2CppClass *nis = find_class("UnityEngineInternal.Input", "NativeInputSystem");
    if (nis) {
        MethodInfo *m = api_class_get_method_from_name(nis, "IOCTL", 4);
        if (!m) for (int i = 0; i <= 6; i++) { m = api_class_get_method_from_name(nis, "IOCTL", i); if (m) break; }
        if (m) patch_method_pointer(m, (void *)hook_ioctl, (void **)&orig_ioctl);
    }

    // Scan __DATA for cached pointers
    if (native_sv) {
        int n = scan_image_data("GameAssembly", (uintptr_t)native_sv, (uintptr_t)hook_supports_vibration);
        viblog("SupportsVibration cache: %d replacements", n);
    }
    if (native_io) {
        int n = scan_image_data("GameAssembly", (uintptr_t)native_io, (uintptr_t)hook_ioctl);
        viblog("IOCTL cache: %d replacements", n);
    }

    viblog("--- Hooks installed ---");
}

// ============ Init Thread ============

static void *init_thread(void *arg) {
    viblog("Waiting for IL2CPP...");

    for (int i = 0; i < 120; i++) {
        usleep(500000);
        if (resolve_il2cpp_api()) {
            viblog("IL2CPP ready (attempt %d)", i + 1);
            install_hooks();

            dispatch_async(dispatch_get_main_queue(), ^{
                initControllerMonitoring();
            });

            // Start HID fallback thread immediately
            pthread_t hid_t;
            pthread_create(&hid_t, NULL, hid_thread, NULL);
            pthread_detach(hid_t);

            // Pre-init Steam Input with retries (60 attempts = 30 seconds)
            for (int retry = 0; retry < 60; retry++) {
                usleep(500000);
                g_steamReady = 0;
                initSteamInput();
                if (g_steamReady == 1) {
                    viblog("Steam Input ready (attempt %d)", retry + 1);
                    break;
                }
                // If HID fallback is already working, stop retrying Steam
                if (g_hid_ready && retry >= 10) {
                    viblog("Steam Input unavailable, using HID fallback");
                    break;
                }
            }

            // Test vibration with whatever output is available
            if (g_steamReady == 1 || g_hid_ready) {
                do_test_vibration();
            } else {
                viblog("WARNING: no vibration output available (Steam=%d HID=%d)", g_steamReady, g_hid_ready);
            }

            return NULL;
        }
    }
    viblog("TIMEOUT: IL2CPP never became available");
    return NULL;
}

// ============ Controller Monitoring ============

static void initControllerMonitoring(void) {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidConnectNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            GCController *c = note.object;
            viblog("Controller connected: '%s'", c.vendorName.UTF8String);
        }];
    [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidDisconnectNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            viblog("Controller disconnected");
            g_curLow = g_curHigh = -1.0f;
        }];
}

// ============ Entry Point ============

__attribute__((constructor))
static void vibfix_init(void) {
    find_install_dir();

    viblog("=== Vibration Fix v" VERSION " loaded (pid=%d) ===", getpid());
    viblog("Install dir: %s", g_install_dir);

    load_config();

    pthread_t thread;
    pthread_create(&thread, NULL, init_thread, NULL);
    pthread_detach(thread);
}
