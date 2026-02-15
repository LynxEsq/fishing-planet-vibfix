// Wrapper launcher for Fishing Planet
// Replaces the original binary, sets DYLD_INSERT_LIBRARIES, then exec()'s the real game

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <mach-o/dyld.h>

int main(int argc, char *argv[]) {
    // Get path to this executable
    char exe_path[4096];
    uint32_t size = sizeof(exe_path);
    if (_NSGetExecutablePath(exe_path, &size) != 0) {
        fprintf(stderr, "[VibFix Launcher] Failed to get executable path\n");
        return 1;
    }

    // Resolve symlinks
    char real_path[4096];
    if (!realpath(exe_path, real_path)) {
        fprintf(stderr, "[VibFix Launcher] Failed to resolve path\n");
        return 1;
    }

    // Build path to the real binary (same directory, named FishingPlanet_real)
    char *dir = dirname(real_path);
    char real_binary[4096];
    snprintf(real_binary, sizeof(real_binary), "%s/FishingPlanet_real", dir);

    // Dylib path — use /tmp to avoid invalidating the app bundle signature
    const char *dylib_path = "/tmp/vibration_fix/vibration_fix.dylib";

    // Check files exist
    if (access(real_binary, X_OK) != 0) {
        fprintf(stderr, "[VibFix Launcher] Real binary not found: %s\n", real_binary);
        return 1;
    }
    if (access(dylib_path, R_OK) != 0) {
        fprintf(stderr, "[VibFix Launcher] Dylib not found: %s\n", dylib_path);
        // Continue without the fix
        fprintf(stderr, "[VibFix Launcher] Launching without vibration fix\n");
        argv[0] = real_binary;
        execv(real_binary, argv);
        perror("execv");
        return 1;
    }

    // Set the environment variable
    setenv("DYLD_INSERT_LIBRARIES", dylib_path, 1);
    fprintf(stderr, "[VibFix Launcher] DYLD_INSERT_LIBRARIES=%s\n", dylib_path);
    fprintf(stderr, "[VibFix Launcher] Launching: %s\n", real_binary);

    // Replace this process with the real game
    argv[0] = real_binary;
    execv(real_binary, argv);

    // If we get here, exec failed
    perror("[VibFix Launcher] execv failed");
    return 1;
}
