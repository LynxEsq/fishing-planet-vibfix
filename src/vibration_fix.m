// vibration_fix.m — Entry point for Fishing Planet Vibration Fix
//
// Hooks Unity's IL2CPP runtime via DYLD_INSERT_LIBRARIES to intercept vibration
// commands (IOCTL RMBL) and redirect them through Steam's Input API.
// Falls back to direct IOKit HID rumble if Steam Input is unavailable.

#include "vibfix.h"

// ============ Init Thread ============

static void *init_thread(void *arg) {
    viblog("Waiting for IL2CPP...");

    for (int i = 0; i < 120; i++) {
        usleep(500000);
        if (resolve_il2cpp_api()) {
            viblog("IL2CPP ready (attempt %d)", i + 1);
            install_hooks();

            // Start fish info HUD overlay
            initHUD();

            // Start fight vibration thread (reads fishing hook data at 20Hz)
            pthread_t fight_t;
            pthread_create(&fight_t, NULL, fight_vibration_thread, NULL);
            pthread_detach(fight_t);

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

void initControllerMonitoring(void) {
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
        }];
}

// ============ Entry Point ============

__attribute__((constructor))
static void vibfix_init(void) {
    find_install_dir();
    install_crash_handler();

    viblog("=== Vibration Fix v" VERSION " loaded (pid=%d) ===", getpid());
    viblog("Install dir: %s", g_install_dir);

    load_config();

    pthread_t thread;
    pthread_create(&thread, NULL, init_thread, NULL);
    pthread_detach(thread);
}

// ============ Shutdown ============

__attribute__((destructor))
static void vibfix_shutdown(void) {
    g_shutting_down = 1;
    viblog("=== Vibration Fix shutting down ===");
    usleep(100000);  // 100ms — let threads see the flag and exit
}
