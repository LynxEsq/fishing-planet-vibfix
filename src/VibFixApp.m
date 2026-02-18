// VibFixApp.m — Native macOS GUI for Fishing Planet Vibration Fix

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#define VERSION "9.0"

// ── Colors ──
#define FP_BG      [NSColor colorWithSRGBRed:0.055 green:0.082 blue:0.125 alpha:1.0]
#define FP_ACCENT  [NSColor colorWithSRGBRed:0.0   green:0.62  blue:0.64  alpha:1.0]
#define FP_TEXT    [NSColor colorWithSRGBRed:0.82  green:0.87  blue:0.92  alpha:1.0]
#define FP_DIM     [NSColor colorWithSRGBRed:0.40  green:0.45  blue:0.50  alpha:1.0]
#define FP_SEP     [NSColor colorWithSRGBRed:0.15  green:0.19  blue:0.25  alpha:1.0]
#define FP_WARN    [NSColor colorWithSRGBRed:0.85  green:0.55  blue:0.20  alpha:1.0]

// ── Localization ──
static int g_lang = 0; // 0=EN, 1=RU

static NSDictionary *L(void) {
    static NSDictionary *en, *ru;
    if (!en) {
        en = @{
            @"status_on":  @"Installed — Steam Launch Options configured",
            @"status_off": @"Not installed — click Install",
            @"install":    @"Install", @"uninstall": @"Uninstall",
            @"save":       @"Save Config", @"working": @"Working...",
            @"done":       @"Done", @"error": @"Error",
            @"saved_t":    @"Config Saved",
            @"saved_i":    @"Changes apply on next game restart.",
            @"steam_t":    @"Steam is Running",
            @"steam_i":    @"Close Steam completely first.\nSteam overwrites config on exit.",
            @"bite_t":     @"BITE — FISH STRIKES THE HOOK",
            @"bite_d":     @"Strong vibration when a fish bites",
            @"reel_t":     @"REEL — PULLING THE FISH IN",
            @"reel_d":     @"Continuous vibration while reeling",
            @"heavy":      @"Heavy Rumble",   @"heavy_tip": @"Low-freq motor — deep thump",
            @"light":      @"Light Buzz",     @"light_tip": @"High-freq motor — light whirr",
            @"ltrig":      @"L2 Trigger Motor", @"trig_tip": @"Vibration in trigger buttons (Xbox Elite / DualSense only)",
            @"rtrig":      @"R2 Trigger Motor",
            @"dbl":        @"Double Tap",     @"dbl_tip":   @"Two quick hits instead of one",
            @"dbl_str":    @"2nd Hit",        @"dbl_str_tip": @"Strength of the second hit",
            @"test":       @"Test vibration on start", @"test_tip": @"Short buzz when game launches",
            @"verbose":    @"Verbose logging",  @"verbose_tip": @"Log every vibration request",
        };
        ru = @{
            @"status_on":  @"Установлено — Launch Options настроены в Steam",
            @"status_off": @"Не установлено — нажмите Установить",
            @"install":    @"Установить", @"uninstall": @"Удалить",
            @"save":       @"Сохранить", @"working": @"Работаем...",
            @"done":       @"Готово", @"error": @"Ошибка",
            @"saved_t":    @"Сохранено",
            @"saved_i":    @"Изменения применятся при следующем запуске игры.",
            @"steam_t":    @"Steam запущен",
            @"steam_i":    @"Сначала закройте Steam полностью.\nSteam перезаписывает настройки при выходе.",
            @"bite_t":     @"ПОКЛЁВКА",
            @"bite_d":     @"Сильная вибрация когда рыба клюёт",
            @"reel_t":     @"ВЫВАЖИВАНИЕ",
            @"reel_d":     @"Вибрация при подмотке и вытягивании",
            @"heavy":      @"Тяжёлый мотор",  @"heavy_tip": @"Низкочастотный — глубокий удар",
            @"light":      @"Лёгкий мотор",   @"light_tip": @"Высокочастотный — лёгкое жужжание",
            @"ltrig":      @"Мотор L2 курка",  @"trig_tip":  @"Вибрация в курках (только Xbox Elite / DualSense)",
            @"rtrig":      @"Мотор R2 курка",
            @"dbl":        @"Двойной удар",    @"dbl_tip":   @"Два коротких удара вместо одного",
            @"dbl_str":    @"Сила 2-го",       @"dbl_str_tip": @"Сила второго удара",
            @"test":       @"Тест вибрации при запуске", @"test_tip": @"Короткая вибрация при старте игры",
            @"verbose":    @"Подробный лог",    @"verbose_tip": @"Логировать каждый запрос вибрации",
        };
    }
    return g_lang == 0 ? en : ru;
}
#define S(k) (L()[(k)] ?: (k))

// ── Helpers ──
@interface FlippedView : NSView @end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSTextField *makeLabel(NSString *text, CGFloat size, NSColor *color, BOOL bold) {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    l.textColor = color;
    l.backgroundColor = [NSColor clearColor];
    return l;
}

// ── AppDelegate ──
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSWindow *window;
@property (strong) NSTextField *statusLabel;
@property (strong) NSButton *installBtn, *uninstallBtn, *langBtn;
@property (strong) NSMutableDictionary<NSString*,NSSlider*> *sliders;
@property (strong) NSMutableDictionary<NSString*,NSTextField*> *sliderLabels;
@property (strong) NSMapTable *sliderToKey;
@property (strong) NSMutableDictionary<NSString*,NSButton*> *checks;
@property (strong) NSString *projectDir;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.sliders = [NSMutableDictionary new];
    self.sliderLabels = [NSMutableDictionary new];
    self.sliderToKey = [NSMapTable strongToStrongObjectsMapTable];
    self.checks = [NSMutableDictionary new];
    self.projectDir = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];

    [self setupAppIcon];
    [self buildWindow];
    [self buildContent];
    [self loadConfig];
    [self refreshStatus];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)a { return YES; }

// ── App Icon ──
- (void)setupAppIcon {
    NSImage *icon = [NSImage imageWithSize:NSMakeSize(512,512) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r,20,20) xRadius:90 yRadius:90];
        NSGradient *g = [[NSGradient alloc]
            initWithStartingColor:[NSColor colorWithSRGBRed:0.06 green:0.10 blue:0.16 alpha:1]
            endingColor:[NSColor colorWithSRGBRed:0.04 green:0.06 blue:0.10 alpha:1]];
        [g drawInBezierPath:bg angle:270];
        [[NSColor colorWithSRGBRed:0 green:0.6 blue:0.65 alpha:0.4] setStroke];
        bg.lineWidth = 6; [bg stroke];
        NSImage *sym = [NSImage imageWithSystemSymbolName:@"gamecontroller.fill" accessibilityDescription:nil];
        if (sym) {
            sym = [sym imageWithSymbolConfiguration:
                [NSImageSymbolConfiguration configurationWithPointSize:160 weight:NSFontWeightMedium]];
            NSImage *t = [NSImage imageWithSize:NSMakeSize(300,200) flipped:NO drawingHandler:^BOOL(NSRect tr) {
                [sym drawInRect:tr fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
                [[NSColor colorWithSRGBRed:0 green:0.65 blue:0.68 alpha:1] set];
                NSRectFillUsingOperation(tr, NSCompositingOperationSourceAtop);
                return YES;
            }];
            [t drawInRect:NSMakeRect(106,156,300,200) fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver fraction:1];
        }
        return YES;
    }];
    [NSApp setApplicationIconImage:icon];
}

// ── Window (created once) ──
- (void)buildWindow {
    NSUInteger mask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                      NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,520,740)
                                              styleMask:mask backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"VibFix";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.backgroundColor = FP_BG;

    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:self.window.contentView.bounds];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    sv.drawsBackground = NO;
    sv.automaticallyAdjustsContentInsets = NO;
    sv.contentInsets = NSEdgeInsetsZero;
    self.window.contentView = sv;
}

// ── Content (rebuilt on language change) ──
- (void)buildContent {
    NSScrollView *sv = (NSScrollView *)self.window.contentView;
    CGFloat W = 520;

    [self.sliders removeAllObjects];
    [self.sliderLabels removeAllObjects];
    [self.sliderToKey removeAllObjects];
    [self.checks removeAllObjects];

    FlippedView *doc = [[FlippedView alloc] initWithFrame:NSMakeRect(0,0,W,900)];
    doc.wantsLayer = YES;
    doc.layer.backgroundColor = [FP_BG CGColor];
    sv.documentView = doc;

    CGFloat y = 0;

    // ── Banner ──
    CGFloat hH = 140;
    NSString *imgPath = [self.projectDir stringByAppendingPathComponent:@"assets/back.png"];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:imgPath];
    if (img) {
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0,y,W,hH)];
        box.wantsLayer = YES;
        box.layer.contents = (__bridge id)[img CGImageForProposedRect:NULL context:nil hints:nil];
        box.layer.contentsGravity = kCAGravityResizeAspectFill;
        box.layer.masksToBounds = YES;
        CAGradientLayer *fade = [CAGradientLayer layer];
        fade.frame = CGRectMake(0, hH-50, W, 50);
        fade.colors = @[(__bridge id)[[NSColor clearColor] CGColor], (__bridge id)[FP_BG CGColor]];
        [box.layer addSublayer:fade];
        [doc addSubview:box];
        y += hH;
    }

    // ── Controls ──
    NSStackView *st = [NSStackView new];
    st.orientation = NSUserInterfaceLayoutOrientationVertical;
    st.alignment = NSLayoutAttributeLeading;
    st.spacing = 7;
    st.edgeInsets = NSEdgeInsetsMake(6, 28, 20, 28);

    // Language toggle + Status
    self.langBtn = [NSButton buttonWithTitle:(g_lang==0 ? @"RU" : @"EN")
                                      target:self action:@selector(toggleLang:)];
    self.langBtn.wantsLayer = YES;
    self.langBtn.contentTintColor = FP_ACCENT;
    self.statusLabel = makeLabel(@"", 12, FP_DIM, NO);
    NSStackView *topRow = [NSStackView stackViewWithViews:@[self.statusLabel, self.langBtn]];
    topRow.spacing = 8;
    [st addArrangedSubview:topRow];

    // Buttons
    self.installBtn = [self btn:S(@"install") action:@selector(doInstall:)];
    self.uninstallBtn = [self btn:S(@"uninstall") action:@selector(doUninstall:)];
    NSStackView *br = [NSStackView stackViewWithViews:@[self.installBtn, self.uninstallBtn]];
    br.spacing = 12;
    [st addArrangedSubview:br];

    [st addArrangedSubview:[self sep]];

    // ── Bite ──
    [st addArrangedSubview:makeLabel(S(@"bite_t"), 11, FP_ACCENT, YES)];
    [st addArrangedSubview:makeLabel(S(@"bite_d"), 10, FP_DIM, NO)];
    [st addArrangedSubview:[self sl:S(@"heavy") key:@"bite_left_motor" val:100 tip:S(@"heavy_tip")]];
    [st addArrangedSubview:[self sl:S(@"light") key:@"bite_right_motor" val:50 tip:S(@"light_tip")]];
    [st addArrangedSubview:[self sl:S(@"ltrig") key:@"bite_left_trigger" val:40 tip:S(@"trig_tip")]];
    [st addArrangedSubview:[self sl:S(@"rtrig") key:@"bite_right_trigger" val:50 tip:S(@"trig_tip")]];
    [st addArrangedSubview:[self chk:S(@"dbl") key:@"bite_double_tap" on:YES tip:S(@"dbl_tip")]];
    [st addArrangedSubview:[self sl:S(@"dbl_str") key:@"bite_double_tap_strength" val:75 tip:S(@"dbl_str_tip")]];

    [st addArrangedSubview:[self sep]];

    // ── Reel ──
    [st addArrangedSubview:makeLabel(S(@"reel_t"), 11, FP_ACCENT, YES)];
    [st addArrangedSubview:makeLabel(S(@"reel_d"), 10, FP_DIM, NO)];
    [st addArrangedSubview:[self sl:S(@"heavy") key:@"reel_left_motor" val:45 tip:S(@"heavy_tip")]];
    [st addArrangedSubview:[self sl:S(@"light") key:@"reel_right_motor" val:100 tip:S(@"light_tip")]];
    [st addArrangedSubview:[self sl:S(@"ltrig") key:@"reel_left_trigger" val:30 tip:S(@"trig_tip")]];
    [st addArrangedSubview:[self sl:S(@"rtrig") key:@"reel_right_trigger" val:50 tip:S(@"trig_tip")]];

    [st addArrangedSubview:[self sep]];

    // ── General ──
    [st addArrangedSubview:[self chk:S(@"test") key:@"test_on_start" on:YES tip:S(@"test_tip")]];
    [st addArrangedSubview:[self chk:S(@"verbose") key:@"verbose_log" on:YES tip:S(@"verbose_tip")]];
    [st addArrangedSubview:[self sep]];

    NSButton *saveBtn = [self btn:S(@"save") action:@selector(doSave:)];
    [st addArrangedSubview:saveBtn];

    NSSize fit = [st fittingSize];
    st.frame = NSMakeRect(0, y, W, fit.height);
    [doc addSubview:st];
    y += fit.height;
    doc.frame = NSMakeRect(0, 0, W, y);

    // Resize window to fit content
    NSRect frame = self.window.frame;
    CGFloat newH = y;
    frame.origin.y += frame.size.height - newH;
    frame.size.height = newH;
    [self.window setFrame:frame display:YES animate:NO];
}

// ── UI factories ──
- (NSButton *)btn:(NSString *)title action:(SEL)a {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:a];
    b.wantsLayer = YES;
    b.contentTintColor = FP_ACCENT;
    return b;
}

- (NSView *)sl:(NSString *)label key:(NSString *)key val:(int)val tip:(NSString *)tip {
    NSTextField *lbl = makeLabel(label, 12, FP_TEXT, NO);
    lbl.alignment = NSTextAlignmentRight;
    lbl.toolTip = tip;
    [lbl.widthAnchor constraintEqualToConstant:120].active = YES;

    NSSlider *s = [NSSlider sliderWithValue:val minValue:0 maxValue:100
                                     target:self action:@selector(sliderMoved:)];
    s.continuous = YES;
    s.toolTip = tip;
    s.trackFillColor = FP_ACCENT;
    [s.widthAnchor constraintEqualToConstant:195].active = YES;

    NSTextField *v = makeLabel([NSString stringWithFormat:@"%d%%", val], 12, FP_DIM, NO);
    v.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [v.widthAnchor constraintEqualToConstant:40].active = YES;

    self.sliders[key] = s;
    self.sliderLabels[key] = v;
    [self.sliderToKey setObject:key forKey:s];

    NSStackView *row = [NSStackView stackViewWithViews:@[lbl, s, v]];
    row.spacing = 8;
    return row;
}

- (NSView *)chk:(NSString *)label key:(NSString *)key on:(BOOL)on tip:(NSString *)tip {
    NSButton *b = [NSButton checkboxWithTitle:label target:nil action:nil];
    b.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    b.contentTintColor = FP_ACCENT;
    b.toolTip = tip;
    ((NSButtonCell *)b.cell).attributedTitle =
        [[NSAttributedString alloc] initWithString:label
            attributes:@{NSForegroundColorAttributeName: FP_TEXT,
                         NSFontAttributeName: [NSFont systemFontOfSize:12]}];
    self.checks[key] = b;
    return b;
}

- (NSView *)sep {
    NSView *v = [[NSView alloc] init];
    v.wantsLayer = YES;
    v.layer.backgroundColor = [FP_SEP CGColor];
    [v.heightAnchor constraintEqualToConstant:1].active = YES;
    [v.widthAnchor constraintEqualToConstant:460].active = YES;
    return v;
}

// ── Language toggle ──
- (void)toggleLang:(id)sender {
    // Save current values
    NSMutableDictionary *sv = [NSMutableDictionary new];
    for (NSString *k in self.sliders) sv[k] = @(self.sliders[k].integerValue);
    NSMutableDictionary *cv = [NSMutableDictionary new];
    for (NSString *k in self.checks) cv[k] = @(self.checks[k].state == NSControlStateValueOn);

    g_lang = 1 - g_lang;
    [self buildContent];

    // Restore values
    for (NSString *k in sv) {
        NSSlider *s = self.sliders[k];
        if (s) { s.integerValue = [sv[k] integerValue];
            self.sliderLabels[k].stringValue = [NSString stringWithFormat:@"%d%%", (int)s.integerValue]; }
    }
    for (NSString *k in cv) {
        NSButton *b = self.checks[k];
        if (b) b.state = [cv[k] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self refreshStatus];
}

// ── Slider action ──
- (void)sliderMoved:(NSSlider *)sender {
    NSString *k = [self.sliderToKey objectForKey:sender];
    if (k && self.sliderLabels[k])
        self.sliderLabels[k].stringValue = [NSString stringWithFormat:@"%d%%", (int)sender.integerValue];
}

// ── Config ──
- (void)loadConfig {
    NSString *path = [self.projectDir stringByAppendingPathComponent:@"config.txt"];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) return;
    for (NSString *line in [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length == 0 || [t hasPrefix:@"#"]) continue;
        NSRange eq = [t rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [[t substringToIndex:eq.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *val = [[t substringFromIndex:eq.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSSlider *s = self.sliders[key];
        if (s) { s.integerValue = [val integerValue];
            self.sliderLabels[key].stringValue = [NSString stringWithFormat:@"%d%%", (int)s.integerValue]; }
        NSButton *c = self.checks[key];
        if (c) c.state = ([val isEqualToString:@"true"]||[val isEqualToString:@"1"]) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (int)iv:(NSString*)k { return (int)self.sliders[k].integerValue; }
- (NSString*)bv:(NSString*)k { return self.checks[k].state==NSControlStateValueOn ? @"true" : @"false"; }

- (void)doSave:(id)sender {
    [self saveConfig];
    [self alert:S(@"saved_t") info:S(@"saved_i")];
}

- (void)saveConfig {
    NSMutableString *c = [NSMutableString string];
    [c appendString:@"# Fishing Planet Vibration Fix — Configuration\n"];
    [c appendString:@"# Values are 0-100 (percentage of motor strength).\n\n"];
    [c appendString:@"# --- Bite (fish strikes the hook) ---\n"];
    [c appendFormat:@"bite_left_motor = %d\n", [self iv:@"bite_left_motor"]];
    [c appendFormat:@"bite_right_motor = %d\n", [self iv:@"bite_right_motor"]];
    [c appendFormat:@"bite_left_trigger = %d\n", [self iv:@"bite_left_trigger"]];
    [c appendFormat:@"bite_right_trigger = %d\n", [self iv:@"bite_right_trigger"]];
    [c appendFormat:@"bite_double_tap = %@\n", [self bv:@"bite_double_tap"]];
    [c appendFormat:@"bite_double_tap_strength = %d\n", [self iv:@"bite_double_tap_strength"]];
    [c appendString:@"\n# --- Reel (pulling the fish in) ---\n"];
    [c appendFormat:@"reel_left_motor = %d\n", [self iv:@"reel_left_motor"]];
    [c appendFormat:@"reel_right_motor = %d\n", [self iv:@"reel_right_motor"]];
    [c appendFormat:@"reel_left_trigger = %d\n", [self iv:@"reel_left_trigger"]];
    [c appendFormat:@"reel_right_trigger = %d\n", [self iv:@"reel_right_trigger"]];
    [c appendString:@"\n# --- General ---\n"];
    [c appendFormat:@"test_on_start = %@\n", [self bv:@"test_on_start"]];
    [c appendFormat:@"verbose_log = %@\n", [self bv:@"verbose_log"]];
    NSString *path = [self.projectDir stringByAppendingPathComponent:@"config.txt"];
    [c writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// ── Status ──
- (void)refreshStatus {
    BOOL on = [self isInstalled];
    self.statusLabel.stringValue = on ? S(@"status_on") : S(@"status_off");
    self.statusLabel.textColor = on ? FP_ACCENT : FP_WARN;
}

- (BOOL)isInstalled {
    NSString *ud = [NSString stringWithFormat:@"%@/Library/Application Support/Steam/userdata", NSHomeDirectory()];
    for (NSString *d in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:ud error:nil]) {
        NSString *vdf = [NSString stringWithFormat:@"%@/%@/config/localconfig.vdf", ud, d];
        NSString *c = [NSString stringWithContentsOfFile:vdf encoding:NSUTF8StringEncoding error:nil];
        if (c && [c containsString:@"vibfix"]) return YES;
    }
    return NO;
}

- (BOOL)isSteamRunning {
    for (NSRunningApplication *a in [[NSWorkspace sharedWorkspace] runningApplications])
        if ([a.bundleIdentifier isEqualToString:@"com.valvesoftware.steam"]) return YES;
    return NO;
}

// ── Install / Uninstall ──
- (void)doInstall:(id)sender {
    if ([self isSteamRunning]) { [self alert:S(@"steam_t") info:S(@"steam_i")]; return; }
    [self saveConfig];
    [self runScript:@"scripts/install.sh" button:self.installBtn];
}
- (void)doUninstall:(id)sender {
    if ([self isSteamRunning]) { [self alert:S(@"steam_t") info:S(@"steam_i")]; return; }
    [self runScript:@"scripts/uninstall.sh" button:self.uninstallBtn];
}

- (void)runScript:(NSString *)name button:(NSButton *)b {
    NSString *path = [self.projectDir stringByAppendingPathComponent:name];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self alert:S(@"error") info:[NSString stringWithFormat:@"Missing: %@", path]]; return;
    }
    b.enabled = NO;
    self.statusLabel.stringValue = S(@"working");
    self.statusLabel.textColor = FP_DIM;

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        NSTask *t = [[NSTask alloc] init];
        t.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
        t.arguments = @[path];
        t.currentDirectoryURL = [NSURL fileURLWithPath:self.projectDir];
        NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
        env[@"VIBFIX_SKIP_STEAM_CHECK"] = @"1";
        t.environment = env;
        NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = p;
        [t launchAndReturnError:nil];
        [t waitUntilExit];
        NSString *out = [[NSString alloc] initWithData:[[p fileHandleForReading] readDataToEndOfFile]
                                              encoding:NSUTF8StringEncoding];
        dispatch_async(dispatch_get_main_queue(), ^{
            b.enabled = YES;
            [self alert:(t.terminationStatus==0 ? S(@"done") : S(@"error")) info:out ?: @""];
            [self refreshStatus];
        });
    });
}

- (void)alert:(NSString *)t info:(NSString *)i {
    NSAlert *a = [NSAlert new]; a.messageText = t; a.informativeText = i ?: @""; [a runModal];
}

@end

// ── Main ──
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        app.delegate = [[AppDelegate alloc] init];
        NSMenu *mb = [NSMenu new];
        NSMenuItem *mi = [NSMenuItem new]; [mb addItem:mi];
        NSMenu *am = [[NSMenu alloc] initWithTitle:@"VibFix"];
        [am addItemWithTitle:@"Quit VibFix" action:@selector(terminate:) keyEquivalent:@"q"];
        mi.submenu = am; app.mainMenu = mb;
        [app run];
    }
    return 0;
}
