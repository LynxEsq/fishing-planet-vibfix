// vibfix_config.c — Install dir detection, configuration, logging

#include "vibfix.h"

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
