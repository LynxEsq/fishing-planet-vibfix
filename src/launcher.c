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

    // Read dylib path from .vibfix_dylib_path (written by install.sh)
    char config_path[4096];
    snprintf(config_path, sizeof(config_path), "%s/.vibfix_dylib_path", dir);

    char dylib_path[4096] = {0};
    FILE *f = fopen(config_path, "r");
    if (f) {
        if (fgets(dylib_path, sizeof(dylib_path), f)) {
            // Strip trailing newline
            size_t len = strlen(dylib_path);
            while (len > 0 && (dylib_path[len-1] == '\n' || dylib_path[len-1] == '\r'))
                dylib_path[--len] = '\0';
        }
        fclose(f);
    }

    if (dylib_path[0] == '\0') {
        fprintf(stderr, "[VibFix Launcher] Config not found: %s\n", config_path);
        fprintf(stderr, "[VibFix Launcher] Launching without vibration fix\n");
        argv[0] = real_binary;
        execv(real_binary, argv);
        perror("execv");
        return 1;
    }

    // Check files exist
    if (access(real_binary, X_OK) != 0) {
        fprintf(stderr, "[VibFix Launcher] Real binary not found: %s\n", real_binary);
        return 1;
    }
    if (access(dylib_path, R_OK) != 0) {
        fprintf(stderr, "[VibFix Launcher] Dylib not found: %s\n", dylib_path);
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
