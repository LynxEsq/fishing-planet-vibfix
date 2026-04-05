// vibfix.h — Shared header for Fishing Planet Vibration Fix
#ifndef VIBFIX_H
#define VIBFIX_H

// C headers (safe for .c and .m)
#include <dlfcn.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
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

// Objective-C frameworks (only in .m files)
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <IOKit/hid/IOHIDManager.h>
#else
#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>
// Forward-declare IOKit HID types for C files
typedef struct __IOHIDDevice *IOHIDDeviceRef;
#endif

#define VERSION "9.1"

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

    // Fight: Fish Force (steady background vibration from fish strength)
    float fish_left;
    float fish_right;
    float fish_trigger_left;
    float fish_trigger_right;

    // Fight: Rod Force (dynamic from rod strain)
    float rod_left;
    float rod_right;
    float rod_trigger_left;
    float rod_trigger_right;

    // Fight: Line Tension
    float tension_left;
    float tension_right;
    float tension_trigger_left;
    float tension_trigger_right;

    // Fight: Haptic Pulse (short burst when game triggers TriggerHapticPulseOnRod)
    float pulse_left;
    float pulse_right;
    float pulse_trigger_left;
    float pulse_trigger_right;

    int   test_on_start;
    int   verbose_log;
} VibConfig;

extern VibConfig g_cfg;
extern char g_install_dir[1024];

// ============ Logging ============

void viblog(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// ============ Config / Utility ============

void find_install_dir(void);
void load_config(void);
void install_crash_handler(void);
float clampf(float v);

// Safe memory access (sigsetjmp guard for calling IL2CPP with potentially stale pointers)
#include <setjmp.h>
int safe_call_active(void);
sigjmp_buf *safe_call_jmpbuf(void);
void safe_call_set_active(int v);

// Usage: if (sigsetjmp(*safe_call_jmpbuf(), 1) == 0) { safe_call_set_active(1); ...; safe_call_set_active(0); }
//        else { /* caught SIGSEGV/SIGBUS — pointer was stale */ }

// ============ IL2CPP API ============

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

// Field introspection (for reading fields from game object instances)
typedef void* Il2CppFieldInfo;
typedef Il2CppFieldInfo (*il2cpp_class_get_fields_t)(Il2CppClass *klass, void **iter);
typedef const char* (*il2cpp_field_get_name_t)(Il2CppFieldInfo field);
typedef size_t (*il2cpp_field_get_offset_t)(Il2CppFieldInfo field);
typedef int (*il2cpp_method_get_param_count_t)(const MethodInfo *method);

// Class iteration (for scanning all classes to find methods)
typedef size_t (*il2cpp_image_get_class_count_t)(Il2CppImage *image);
typedef Il2CppClass* (*il2cpp_image_get_class_t)(Il2CppImage *image, size_t index);
typedef const char* (*il2cpp_class_get_name_t)(Il2CppClass *klass);
typedef const char* (*il2cpp_class_get_namespace_t)(Il2CppClass *klass);

extern il2cpp_domain_get_t api_domain_get;
extern il2cpp_domain_get_assemblies_t api_domain_get_assemblies;
extern il2cpp_assembly_get_image_t api_assembly_get_image;
extern il2cpp_class_from_name_t api_class_from_name;
extern il2cpp_class_get_method_from_name_t api_class_get_method_from_name;
extern il2cpp_class_get_methods_t api_class_get_methods;
extern il2cpp_method_get_name_t api_method_get_name;
extern il2cpp_resolve_icall_t api_resolve_icall;
extern il2cpp_add_internal_call_t api_add_internal_call;
extern il2cpp_class_get_fields_t api_class_get_fields;
extern il2cpp_field_get_name_t api_field_get_name;
extern il2cpp_field_get_offset_t api_field_get_offset;
extern il2cpp_method_get_param_count_t api_method_get_param_count;
extern il2cpp_image_get_class_count_t api_image_get_class_count;
extern il2cpp_image_get_class_t api_image_get_class;
extern il2cpp_class_get_name_t api_class_get_name;
extern il2cpp_class_get_namespace_t api_class_get_namespace;

// ============ IL2CPP Helpers ============

int resolve_il2cpp_api(void);
Il2CppClass* find_class(const char *ns, const char *name);
void patch_method_pointer(MethodInfo *method, void *new_func, void **save_orig);
int scan_image_data(const char *image_substr, uintptr_t find_val, uintptr_t replace_val);
void install_hooks(void);

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

extern SteamInput_fn api_SteamInput;
extern SteamInputInit_fn api_SteamInputInit;
extern SteamInputRunFrame_fn api_SteamInputRunFrame;
extern GetConnectedControllers_fn api_GetControllers;
extern TriggerVibration_fn api_TriggerVibration;
extern TriggerVibrationExtended_fn api_TriggerVibrationExt;
extern ISteamInput g_steamInput;
extern InputHandle_t g_controllerHandle;
extern int g_steamReady;
extern int g_hid_ready;

// ============ Fishing State (from inline hooks) ============

extern float g_line_tension;
extern float g_line_tension_peak;  // peak-hold: max since last decay (for multi-rod)
extern float g_fish_force;
extern float g_rod_force;
extern float g_reel_speed;   // Reel1stBehaviour.get_CurrentRelativeSpeed (0–1, >0 when reeling)
extern float g_reel_speed_peak;    // peak-hold: max since last decay (for multi-rod)
extern float g_reel_force;
extern float g_reel_force_peak;    // peak-hold: max since last decay (for multi-rod)
extern int   g_fishing_hooks_active;
extern volatile uint32_t g_fish_force_tick;  // increments each time get_CurrentForce is called
extern volatile int g_shutting_down;         // set on process exit to stop threads
extern volatile int g_vibration_disabled;    // set by DSBL ioctl, cleared by ENBL

// ============ Fish HUD Data ============

typedef struct {
    // From Fish1stBehaviour (updated in hook_GetCurrentForce)
    float maxForce;
    float relativeForce;
    float appliedForce;
    float distanceToTackle;
    float mass;
    float fishBehaviourLength;
    int   state;
    int   isHooked;
    int   isBig;
    int   isHuge;
    int   isSmall;
    int   isPassive;
    // Extended Fish1stBehaviour data
    float fishVelocity;       // get_CurrentVelocity (magnitude)
    float fishMaxSpeed;       // get_CurrentMaxSpeed
    float minForce;           // get_MinForce
    float playerForce;        // get_PlayerForce
    float stopFightProb;      // get_StopFightProbability
    float escapeProb;         // get_AllEscapesProbability
    float maneuverProb;       // get_AllManeuversProbability
    float retreatThreshold;   // get_RetreatThreshold
    float biteTime;           // get_BiteTime
    float maxBiteTime;        // get_MaxBiteTime
    int   isShocked;          // get_IsShocked
    int   isShaking;          // get_IsShaking
    int   isTasting;          // get_IsTasting
    int   isFishSwimming;     // get_IsFishSwiming
    int   isInWater;          // get_IsInWater
    // FishAi FSM state & bite mechanics
    char  aiStateName[48];    // Current AI state class name (e.g. "FishAIBite")
    int   striked;            // FishAi.striked — strike was performed
    int   endOfTaste;         // FishAi.endOfTaste — taste period ended
    int   countTastes;        // FishAi.CountTastes — current taste count
    int   amountTastes;       // FishAi.AmountTastes — total tastes before retreat
    // From ObjectModel.Fish (via CaughtFish chain)
    int   hasFishInfo;
    char  name[128];
    float weight;
    float fishLength;
    int   isTrophy;
    int   isUnique;
    int   isMonster;
    float stamina;
    float baseForce;
    float speed;
} FishHUDData;

extern FishHUDData g_hud_data;
extern volatile void *g_fish_thisptr;

// ============ Multi-Fish Slots ============

#define MAX_FISH_SLOTS 8

typedef struct {
    FishHUDData  hud;              // full HUD data for this fish
    void        *fish_ptr;         // Fish1stBehaviour pointer (owner)
    void        *ai_ptr;           // FishAi pointer (key for lookup)
    float        current_force;    // fish force (from ai+0x88 for all, getter for active)
    uint32_t     last_update_tick; // monotonic tick from FishAi.Update
    int          active;           // 1 = player is holding this rod
    int          used;             // 0 = empty slot
} FishSlot;

extern FishSlot g_fish_slots[MAX_FISH_SLOTS];
extern int g_active_slot;
extern volatile uint32_t g_slot_tick;

// Poll CaughtFish data for a slot (called from HUD timer after fight ends)
// Returns 1 if Fish Info was successfully read, 0 otherwise.
int poll_caught_fish(int slot_idx);

void *find_method_addr(const char *class_name, const char *method_name, int arg_count);
void *find_method_addr_ns(const char *ns, const char *class_name, const char *method_name, int arg_count);
void initHUD(void);

// ============ Output ============

void initSteamInput(void);
void send_hid_rumble(uint8_t lt, uint8_t rt, uint8_t left, uint8_t right);
void outputRumble(uint8_t left, uint8_t right, uint8_t lt, uint8_t rt);
void sendRumble(float lowFreq, float highFreq);
void do_test_vibration(void);
void *hid_thread(void *arg);
void *fight_vibration_thread(void *arg);

// ============ Controller Monitoring ============

void initControllerMonitoring(void);

#endif // VIBFIX_H
