// vibfix_config.c — Install dir detection, configuration, logging, crash handler

#include "vibfix.h"
#include <execinfo.h>
#include <signal.h>

// ============ Install Directory Detection ============

char g_install_dir[1024] = "/tmp/vibration_fix";

void find_install_dir(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "vibration_fix.dylib")) {
            strncpy(g_install_dir, name, sizeof(g_install_dir) - 1);
            char *last_slash = strrchr(g_install_dir, '/');
            if (last_slash) *last_slash = '\0';
            // If config.txt not here, try parent dir (dylib may be in build/)
            char test[1024];
            snprintf(test, sizeof(test), "%s/config.txt", g_install_dir);
            if (access(test, R_OK) != 0) {
                last_slash = strrchr(g_install_dir, '/');
                if (last_slash) *last_slash = '\0';
            }
            break;
        }
    }
}

// ============ Configuration ============

VibConfig g_cfg = {
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

    .fish_left = 0.05f,
    .fish_right = 0.10f,
    .fish_trigger_left = 0.0f,
    .fish_trigger_right = 0.05f,

    .rod_left = 0.20f,
    .rod_right = 0.40f,
    .rod_trigger_left = 0.10f,
    .rod_trigger_right = 0.20f,

    .tension_left = 0.10f,
    .tension_right = 0.20f,
    .tension_trigger_left = 0.05f,
    .tension_trigger_right = 0.10f,

    .pulse_left = 0.60f,
    .pulse_right = 0.30f,
    .pulse_trigger_left = 0.20f,
    .pulse_trigger_right = 0.30f,

    .test_on_start = 1,
    .verbose_log = 1,
};

float clampf(float v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

// ============ Logging ============

static FILE *g_logfile = NULL;
static pthread_mutex_t g_logmutex = PTHREAD_MUTEX_INITIALIZER;

void viblog(const char *fmt, ...) {
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

// ============ Crash Handler ============

static const char *signal_name(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGBUS:  return "SIGBUS";
        case SIGILL:  return "SIGILL";
        case SIGABRT: return "SIGABRT";
        case SIGFPE:  return "SIGFPE";
        default:      return "UNKNOWN";
    }
}

// --- Safe memory access: sigsetjmp/siglongjmp guard ---
// When g_safe_jmp_active is set, SIGSEGV/SIGBUS in poll_caught_fish
// will longjmp back instead of crashing the process.
static __thread sigjmp_buf g_safe_jmp;
static __thread volatile int g_safe_jmp_active = 0;

static struct sigaction g_prev_sigsegv;
static struct sigaction g_prev_sigbus;

static void crash_handler(int sig, siginfo_t *info, void *ucontext) {
    // If we're inside a safe_call block, recover instead of crashing
    if (g_safe_jmp_active) {
        g_safe_jmp_active = 0;
        siglongjmp(g_safe_jmp, sig);
        // not reached
    }

    // All I/O here must be async-signal-safe: write() only, no fprintf/malloc
    int fd = g_logfile ? fileno(g_logfile) : -1;
    if (fd < 0) goto reraise;

    // Write crash header
    char buf[512];
    int len = snprintf(buf, sizeof(buf),
        "\n[CRASH] Signal %d (%s) at address %p\n",
        sig, signal_name(sig), info->si_addr);
    write(fd, buf, len);

    // Register context (ARM64)
#if defined(__aarch64__)
    ucontext_t *uc = (ucontext_t *)ucontext;
    if (uc) {
        uintptr_t pc = uc->uc_mcontext->__ss.__pc;
        uintptr_t lr = uc->uc_mcontext->__ss.__lr;
        uintptr_t fp = uc->uc_mcontext->__ss.__fp;
        uintptr_t sp = uc->uc_mcontext->__ss.__sp;
        len = snprintf(buf, sizeof(buf),
            "[CRASH] PC=0x%lx LR=0x%lx FP=0x%lx SP=0x%lx\n",
            (unsigned long)pc, (unsigned long)lr,
            (unsigned long)fp, (unsigned long)sp);
        write(fd, buf, len);

        // Dump x0-x28
        for (int i = 0; i < 29; i += 4) {
            len = snprintf(buf, sizeof(buf),
                "[CRASH] x%d=0x%lx x%d=0x%lx x%d=0x%lx x%d=0x%lx\n",
                i,   (unsigned long)uc->uc_mcontext->__ss.__x[i],
                i+1, (unsigned long)uc->uc_mcontext->__ss.__x[i+1],
                i+2, (unsigned long)uc->uc_mcontext->__ss.__x[i+2],
                i+3, (unsigned long)uc->uc_mcontext->__ss.__x[i+3]);
            write(fd, buf, len);
        }
    }
#endif

    // Backtrace (backtrace() is not strictly async-signal-safe but works in practice on macOS)
    void *bt[64];
    int n = backtrace(bt, 64);
    if (n > 0) {
        write(fd, "[CRASH] Backtrace:\n", 19);
        backtrace_symbols_fd(bt, n, fd);
    }

    // Log fishing state for context
    len = snprintf(buf, sizeof(buf),
        "[CRASH] State: fish_force=%.1f rod_force=%.1f tension=%.1f "
        "fish_ptr=%p slot=%d hooks_active=%d\n",
        g_fish_force, g_rod_force, g_line_tension,
        (void *)g_fish_thisptr, g_active_slot, g_fishing_hooks_active);
    write(fd, buf, len);

reraise:
    // Re-raise to get default crash behavior (core dump / crash report)
    signal(sig, SIG_DFL);
    raise(sig);
}

int safe_call_active(void) { return g_safe_jmp_active; }
sigjmp_buf *safe_call_jmpbuf(void) { return &g_safe_jmp; }
void safe_call_set_active(int v) { g_safe_jmp_active = v; }

void install_crash_handler(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, &g_prev_sigsegv);
    sigaction(SIGBUS,  &sa, &g_prev_sigbus);
    sigaction(SIGILL,  &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGFPE,  &sa, NULL);
}

// ============ Config Loading ============

void load_config(void) {
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
        else if (strcmp(key, "fish_left_motor") == 0)       g_cfg.fish_left = fv;
        else if (strcmp(key, "fish_right_motor") == 0)      g_cfg.fish_right = fv;
        else if (strcmp(key, "fish_left_trigger") == 0)     g_cfg.fish_trigger_left = fv;
        else if (strcmp(key, "fish_right_trigger") == 0)    g_cfg.fish_trigger_right = fv;
        else if (strcmp(key, "rod_left_motor") == 0)        g_cfg.rod_left = fv;
        else if (strcmp(key, "rod_right_motor") == 0)       g_cfg.rod_right = fv;
        else if (strcmp(key, "rod_left_trigger") == 0)      g_cfg.rod_trigger_left = fv;
        else if (strcmp(key, "rod_right_trigger") == 0)     g_cfg.rod_trigger_right = fv;
        else if (strcmp(key, "tension_left_motor") == 0)    g_cfg.tension_left = fv;
        else if (strcmp(key, "tension_right_motor") == 0)   g_cfg.tension_right = fv;
        else if (strcmp(key, "tension_left_trigger") == 0)  g_cfg.tension_trigger_left = fv;
        else if (strcmp(key, "tension_right_trigger") == 0) g_cfg.tension_trigger_right = fv;
        else if (strcmp(key, "pulse_left_motor") == 0)      g_cfg.pulse_left = fv;
        else if (strcmp(key, "pulse_right_motor") == 0)     g_cfg.pulse_right = fv;
        else if (strcmp(key, "pulse_left_trigger") == 0)    g_cfg.pulse_trigger_left = fv;
        else if (strcmp(key, "pulse_right_trigger") == 0)   g_cfg.pulse_trigger_right = fv;
        else if (strcmp(key, "test_on_start") == 0)         g_cfg.test_on_start = is_true;
        else if (strcmp(key, "verbose_log") == 0)           g_cfg.verbose_log = is_true;
    }
    fclose(f);

    viblog("Config: bite L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%% dbl=%d dbl_str=%.0f%%",
           g_cfg.bite_left*100, g_cfg.bite_right*100,
           g_cfg.bite_trigger_left*100, g_cfg.bite_trigger_right*100,
           g_cfg.bite_double_tap, g_cfg.bite_double_tap_strength*100);
    viblog("Config: reel L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%%",
           g_cfg.reel_left*100, g_cfg.reel_right*100,
           g_cfg.reel_trigger_left*100, g_cfg.reel_trigger_right*100);
    viblog("Config: fish L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%%",
           g_cfg.fish_left*100, g_cfg.fish_right*100,
           g_cfg.fish_trigger_left*100, g_cfg.fish_trigger_right*100);
    viblog("Config: rod L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%%",
           g_cfg.rod_left*100, g_cfg.rod_right*100,
           g_cfg.rod_trigger_left*100, g_cfg.rod_trigger_right*100);
    viblog("Config: tension L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%%",
           g_cfg.tension_left*100, g_cfg.tension_right*100,
           g_cfg.tension_trigger_left*100, g_cfg.tension_trigger_right*100);
    viblog("Config: pulse L=%.0f%% R=%.0f%% LT=%.0f%% RT=%.0f%%",
           g_cfg.pulse_left*100, g_cfg.pulse_right*100,
           g_cfg.pulse_trigger_left*100, g_cfg.pulse_trigger_right*100);
    viblog("Config: test_on_start=%d verbose_log=%d", g_cfg.test_on_start, g_cfg.verbose_log);
}
