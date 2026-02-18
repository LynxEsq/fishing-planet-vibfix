// Steam Launch Options wrapper for Fishing Planet vibration fix
//
// Usage: Steam > Fishing Planet > Properties > Launch Options:
//   "/path/to/launch" %command%
//
// Finds vibration_fix.dylib next to itself, sets DYLD_INSERT_LIBRARIES,
// then exec()'s the real game. No game files modified.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <libgen.h>
#include <mach-o/dyld.h>

static FILE *g_logf = NULL;

#define LOG(...) do { \
    if (g_logf) { fprintf(g_logf, __VA_ARGS__); fprintf(g_logf, "\n"); } \
    fprintf(stderr, "[VibFix] " __VA_ARGS__); fprintf(stderr, "\n"); \
} while(0)

// Resolve .app bundle to actual binary inside Contents/MacOS/
static int resolve_app_binary(const char *app_path, char *out, size_t out_size) {
    size_t len = strlen(app_path);
    if (len < 5 || strcmp(app_path + len - 4, ".app") != 0)
        return 0;  // not a .app bundle

    // Extract app name: "/path/to/Foo Bar.app" -> "Foo Bar"
    // Work on a copy to use basename safely
    char tmp[4096];
    strncpy(tmp, app_path, sizeof(tmp) - 1);
    tmp[sizeof(tmp) - 1] = '\0';

    // Remove trailing slash if present
    size_t tlen = strlen(tmp);
    while (tlen > 0 && tmp[tlen - 1] == '/') tmp[--tlen] = '\0';

    // Find last path component
    const char *base = strrchr(tmp, '/');
    base = base ? base + 1 : tmp;

    // Strip .app suffix to get executable name
    char exe_name[256];
    size_t blen = strlen(base);
    if (blen <= 4) return 0;
    strncpy(exe_name, base, blen - 4);
    exe_name[blen - 4] = '\0';

    snprintf(out, out_size, "%s/Contents/MacOS/%s", app_path, exe_name);
    return 1;
}

int main(int argc, char *argv[]) {
    // Find our own directory (dylib is next to us)
    char exe_path[4096];
    uint32_t pathsize = sizeof(exe_path);
    _NSGetExecutablePath(exe_path, &pathsize);
    char resolved[4096];
    realpath(exe_path, resolved);
    char *dir = dirname(resolved);

    // Open log file
    char log_path[4096];
    snprintf(log_path, sizeof(log_path), "%s/launch.log", dir);
    g_logf = fopen(log_path, "w");
    if (g_logf) setbuf(g_logf, NULL);

    LOG("=== VibFix Launch Wrapper ===");
    LOG("argc=%d", argc);
    for (int i = 0; i < argc; i++)
        LOG("argv[%d]='%s'", i, argv[i]);

    const char *existing_dyld = getenv("DYLD_INSERT_LIBRARIES");
    LOG("existing DYLD_INSERT_LIBRARIES='%s'", existing_dyld ? existing_dyld : "(null)");

    if (argc < 2) {
        LOG("ERROR: no game command. Set Steam Launch Options to:");
        LOG("  \"/path/to/launch\" %%command%%");
        if (g_logf) fclose(g_logf);
        return 1;
    }

    // Resolve .app bundle to actual binary
    char game_binary[4096];
    if (resolve_app_binary(argv[1], game_binary, sizeof(game_binary))) {
        LOG("Resolved .app bundle:");
        LOG("  from: %s", argv[1]);
        LOG("  to:   %s", game_binary);
    } else {
        strncpy(game_binary, argv[1], sizeof(game_binary) - 1);
        game_binary[sizeof(game_binary) - 1] = '\0';
    }

    // Build dylib path
    char dylib_path[4096];
    snprintf(dylib_path, sizeof(dylib_path), "%s/vibration_fix.dylib", dir);
    LOG("dylib: %s (exists=%d)", dylib_path, access(dylib_path, R_OK) == 0);
    LOG("game:  %s (exists=%d)", game_binary, access(game_binary, X_OK) == 0);

    if (access(game_binary, X_OK) != 0) {
        LOG("ERROR: game binary not executable: %s", game_binary);
        if (g_logf) fclose(g_logf);
        return 1;
    }

    if (access(dylib_path, R_OK) != 0) {
        LOG("WARNING: dylib not found, launching without fix");
        if (g_logf) fclose(g_logf);
        argv[1] = game_binary;
        execv(game_binary, &argv[1]);
        perror("execv");
        return 1;
    }

    // Append to existing DYLD_INSERT_LIBRARIES (preserve Steam overlay)
    if (existing_dyld && existing_dyld[0]) {
        char combined[8192];
        snprintf(combined, sizeof(combined), "%s:%s", dylib_path, existing_dyld);
        setenv("DYLD_INSERT_LIBRARIES", combined, 1);
        LOG("DYLD_INSERT_LIBRARIES=%s", combined);
    } else {
        setenv("DYLD_INSERT_LIBRARIES", dylib_path, 1);
        LOG("DYLD_INSERT_LIBRARIES=%s", dylib_path);
    }

    LOG("exec: %s", game_binary);
    if (g_logf) fclose(g_logf);

    // Build new argv: game_binary + remaining args (skip argv[0]=wrapper, argv[1]=.app)
    char *new_argv[256];
    new_argv[0] = game_binary;
    for (int i = 2; i < argc && i < 255; i++)
        new_argv[i - 1] = argv[i];
    new_argv[argc - 1] = NULL;

    execv(game_binary, new_argv);

    // exec failed
    g_logf = fopen(log_path, "a");
    LOG("execv FAILED: errno=%d (%s)", errno, strerror(errno));
    if (g_logf) fclose(g_logf);
    return 1;
}
