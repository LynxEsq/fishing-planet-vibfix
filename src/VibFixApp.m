// VibFixApp.m — Native macOS GUI for Fishing Planet Vibration Fix

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/hid/IOHIDManager.h>

#define VERSION "9.0"

// ── Colors ──
#define FP_BG      [NSColor colorWithSRGBRed:0.055 green:0.082 blue:0.125 alpha:1.0]
#define FP_ACCENT  [NSColor colorWithSRGBRed:0.0   green:0.62  blue:0.64  alpha:1.0]
#define FP_TEXT    [NSColor colorWithSRGBRed:0.82  green:0.87  blue:0.92  alpha:1.0]
#define FP_DIM     [NSColor colorWithSRGBRed:0.40  green:0.45  blue:0.50  alpha:1.0]
#define FP_SEP     [NSColor colorWithSRGBRed:0.15  green:0.19  blue:0.25  alpha:1.0]
#define FP_WARN    [NSColor colorWithSRGBRed:0.85  green:0.55  blue:0.20  alpha:1.0]

// ── IOKit HID — Xbox Controller ──
static IOHIDDeviceRef g_xbox_hid = NULL;
static int g_hid_ready = 0;

static const int g_xbox_pids[] = {
    0x0B13, 0x0B20, 0x0B21, 0x0B22, 0x02E0, 0x02FD, 0x0B05, 0x0B12, 0
};
static int is_xbox_pid(int pid) {
    for (int i = 0; g_xbox_pids[i]; i++) if (g_xbox_pids[i] == pid) return 1;
    return 0;
}
static void hid_matched(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (g_hid_ready) return;
    CFNumberRef pidRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
    int32_t pid = 0;
    if (pidRef) CFNumberGetValue(pidRef, kCFNumberSInt32Type, &pid);
    if (is_xbox_pid(pid)) {
        g_xbox_hid = device; CFRetain(device); g_hid_ready = 1;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"HIDStatusChanged" object:nil];
        });
    }
}
static void hid_removed(void *ctx, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (device == g_xbox_hid) {
        g_hid_ready = 0; CFRelease(g_xbox_hid); g_xbox_hid = NULL;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"HIDStatusChanged" object:nil];
        });
    }
}
static void start_hid_search(void) {
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (!mgr) return;
        int vid = 0x045E;
        CFNumberRef vidNum = CFNumberCreate(NULL, kCFNumberIntType, &vid);
        CFStringRef keys[] = { CFSTR(kIOHIDVendorIDKey) };
        CFTypeRef vals[] = { vidNum };
        CFDictionaryRef match = CFDictionaryCreate(NULL, (const void **)keys, (const void **)vals,
            1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDManagerSetDeviceMatching(mgr, match);
        CFRelease(match); CFRelease(vidNum);
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, hid_matched, NULL);
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, hid_removed, NULL);
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDManagerOpen(mgr, kIOHIDOptionsTypeNone);
        CFRunLoopRun();
    });
}
static void send_hid_rumble(uint8_t lt, uint8_t rt, uint8_t left, uint8_t right) {
    if (!g_hid_ready || !g_xbox_hid) return;
    uint8_t report[9] = {0x03, 0x0F, lt, rt, left, right, 0xFF, 0x00, 0xEB};
    IOHIDDeviceSetReport(g_xbox_hid, kIOHIDReportTypeOutput, 0x03, report, sizeof(report));
}

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
            @"reel_t":     @"REEL — DRAG RATCHET CLICK",
            @"reel_d":     @"Pulsing tuk-tuk when reel hits max drag load",
            @"heavy":      @"Heavy Rumble",   @"heavy_tip": @"Low-freq motor — deep thump",
            @"light":      @"Light Buzz",     @"light_tip": @"High-freq motor — light whirr",
            @"ltrig":      @"L2 Trigger Motor", @"trig_tip": @"Vibration in trigger buttons (Xbox Elite / DualSense only)",
            @"rtrig":      @"R2 Trigger Motor",
            @"dbl":        @"Double Tap",     @"dbl_tip":   @"Two quick hits instead of one",
            @"dbl_str":    @"2nd Hit",        @"dbl_str_tip": @"Strength of the second hit",
            @"test":       @"Test vibration on start", @"test_tip": @"Short buzz when game launches",
            @"verbose":    @"Verbose logging",  @"verbose_tip": @"Log every vibration request",
            @"test_bite":  @"Test Bite", @"test_reel": @"Test Reel",
            @"fish_t":     @"FISH FORCE", @"fish_d": @"Background vibration from hooked fish",
            @"rod_t":      @"ROD FORCE",  @"rod_d":  @"Dynamic vibration from rod strain",
            @"tens_t":     @"LINE TENSION", @"tens_d": @"Vibration from line tension",
            @"pulse_t":    @"HAPTIC PULSE", @"pulse_d": @"Short burst when game triggers haptic",
            @"test_fish":  @"Test", @"test_rod": @"Test", @"test_tens": @"Test", @"test_pulse": @"Test",
            @"ctrl_on":    @"Controller connected",
            @"ctrl_off":   @"No controller — connect Xbox via Bluetooth",
            @"no_ctrl_t":  @"No Controller", @"no_ctrl_i": @"Connect Xbox controller via Bluetooth first.",
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
            @"reel_t":     @"КАТУШКА — ЩЕЛЧОК ФРИКЦИОНА",
            @"reel_d":     @"Прерывистая вибрация тук-тук при максимальной нагрузке",
            @"heavy":      @"Тяжёлый мотор",  @"heavy_tip": @"Низкочастотный — глубокий удар",
            @"light":      @"Лёгкий мотор",   @"light_tip": @"Высокочастотный — лёгкое жужжание",
            @"ltrig":      @"Мотор L2 курка",  @"trig_tip":  @"Вибрация в курках (только Xbox Elite / DualSense)",
            @"rtrig":      @"Мотор R2 курка",
            @"dbl":        @"Двойной удар",    @"dbl_tip":   @"Два коротких удара вместо одного",
            @"dbl_str":    @"Сила 2-го",       @"dbl_str_tip": @"Сила второго удара",
            @"test":       @"Тест вибрации при запуске", @"test_tip": @"Короткая вибрация при старте игры",
            @"verbose":    @"Подробный лог",    @"verbose_tip": @"Логировать каждый запрос вибрации",
            @"test_bite":  @"Тест поклёвки", @"test_reel": @"Тест вываживания",
            @"fish_t":     @"СИЛА РЫБЫ", @"fish_d": @"Фоновая вибрация от пойманной рыбы",
            @"rod_t":      @"НАГРУЗКА НА УДОЧКУ", @"rod_d": @"Динамическая вибрация от нагрузки удочки",
            @"tens_t":     @"НАТЯЖЕНИЕ ЛЕСКИ", @"tens_d": @"Вибрация от натяжения лески",
            @"pulse_t":    @"УДАР ПРИ ПОКЛЁВКЕ", @"pulse_d": @"Короткий удар при срабатывании игровой вибрации",
            @"test_fish":  @"Тест", @"test_rod": @"Тест", @"test_tens": @"Тест", @"test_pulse": @"Тест",
            @"ctrl_on":    @"Контроллер подключён",
            @"ctrl_off":   @"Нет контроллера — подключите Xbox по Bluetooth",
            @"no_ctrl_t":  @"Нет контроллера", @"no_ctrl_i": @"Подключите Xbox-контроллер по Bluetooth.",
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
@property (strong) NSTextField *ctrlLabel;
@property (strong) NSMapTable *testBtnToKey;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    self.sliders = [NSMutableDictionary new];
    self.sliderLabels = [NSMutableDictionary new];
    self.sliderToKey = [NSMapTable strongToStrongObjectsMapTable];
    self.testBtnToKey = [NSMapTable strongToStrongObjectsMapTable];
    self.checks = [NSMutableDictionary new];
    self.projectDir = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hidStatusChanged:)
                                                 name:@"HIDStatusChanged" object:nil];
    start_hid_search();

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
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1040,740)
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
    CGFloat W = 1040;
    CGFloat colW = 500;

    [self.sliders removeAllObjects];
    [self.sliderLabels removeAllObjects];
    [self.sliderToKey removeAllObjects];
    [self.testBtnToKey removeAllObjects];
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

    // ── Top bar (full width) ──
    NSStackView *topSt = [NSStackView new];
    topSt.orientation = NSUserInterfaceLayoutOrientationVertical;
    topSt.alignment = NSLayoutAttributeLeading;
    topSt.spacing = 7;
    topSt.edgeInsets = NSEdgeInsetsMake(6, 28, 10, 28);

    self.langBtn = [NSButton buttonWithTitle:(g_lang==0 ? @"RU" : @"EN")
                                      target:self action:@selector(toggleLang:)];
    self.langBtn.wantsLayer = YES;
    self.langBtn.contentTintColor = FP_ACCENT;
    self.statusLabel = makeLabel(@"", 12, FP_DIM, NO);
    NSStackView *topRow = [NSStackView stackViewWithViews:@[self.statusLabel, self.langBtn]];
    topRow.spacing = 8;
    [topSt addArrangedSubview:topRow];

    self.installBtn = [self btn:S(@"install") action:@selector(doInstall:)];
    self.uninstallBtn = [self btn:S(@"uninstall") action:@selector(doUninstall:)];
    NSStackView *br = [NSStackView stackViewWithViews:@[self.installBtn, self.uninstallBtn]];
    br.spacing = 12;
    [topSt addArrangedSubview:br];

    self.ctrlLabel = makeLabel(@"", 11, FP_DIM, NO);
    [topSt addArrangedSubview:self.ctrlLabel];
    [self refreshCtrlStatus];

    NSSize topFit = [topSt fittingSize];
    topSt.frame = NSMakeRect(0, y, W, topFit.height);
    [doc addSubview:topSt];
    y += topFit.height;

    // ── LEFT column: Bite + Reel + General ──
    NSStackView *st = [NSStackView new];
    st.orientation = NSUserInterfaceLayoutOrientationVertical;
    st.alignment = NSLayoutAttributeLeading;
    st.spacing = 7;
    st.edgeInsets = NSEdgeInsetsMake(6, 28, 20, 14);

    [st addArrangedSubview:[self sep]];

    // Bite
    NSButton *testBiteBtn = [self btn:S(@"test_bite") action:@selector(testBite:)];
    testBiteBtn.font = [NSFont systemFontOfSize:10];
    NSStackView *biteHeader = [NSStackView stackViewWithViews:@[
        makeLabel(S(@"bite_t"), 11, FP_ACCENT, YES), testBiteBtn]];
    biteHeader.spacing = 8;
    [st addArrangedSubview:biteHeader];
    [st addArrangedSubview:makeLabel(S(@"bite_d"), 10, FP_DIM, NO)];
    [st addArrangedSubview:[self sl:S(@"heavy") key:@"bite_left_motor" val:100 tip:S(@"heavy_tip")]];
    [st addArrangedSubview:[self sl:S(@"light") key:@"bite_right_motor" val:50 tip:S(@"light_tip")]];
    [st addArrangedSubview:[self sl:S(@"ltrig") key:@"bite_left_trigger" val:40 tip:S(@"trig_tip")]];
    [st addArrangedSubview:[self sl:S(@"rtrig") key:@"bite_right_trigger" val:50 tip:S(@"trig_tip")]];
    [st addArrangedSubview:[self chk:S(@"dbl") key:@"bite_double_tap" on:YES tip:S(@"dbl_tip")]];
    [st addArrangedSubview:[self sl:S(@"dbl_str") key:@"bite_double_tap_strength" val:75 tip:S(@"dbl_str_tip")]];

    [st addArrangedSubview:[self sep]];

    // Reel
    NSButton *testReelBtn = [self btn:S(@"test_reel") action:@selector(testReel:)];
    testReelBtn.font = [NSFont systemFontOfSize:10];
    NSStackView *reelHeader = [NSStackView stackViewWithViews:@[
        makeLabel(S(@"reel_t"), 11, FP_ACCENT, YES), testReelBtn]];
    reelHeader.spacing = 8;
    [st addArrangedSubview:reelHeader];
    [st addArrangedSubview:makeLabel(S(@"reel_d"), 10, FP_DIM, NO)];
    [st addArrangedSubview:[self sl:S(@"heavy") key:@"reel_left_motor" val:45 tip:S(@"heavy_tip")]];
    [st addArrangedSubview:[self sl:S(@"light") key:@"reel_right_motor" val:100 tip:S(@"light_tip")]];
    [st addArrangedSubview:[self sl:S(@"ltrig") key:@"reel_left_trigger" val:30 tip:S(@"trig_tip")]];
    [st addArrangedSubview:[self sl:S(@"rtrig") key:@"reel_right_trigger" val:50 tip:S(@"trig_tip")]];

    [st addArrangedSubview:[self sep]];

    // General
    [st addArrangedSubview:[self chk:S(@"test") key:@"test_on_start" on:YES tip:S(@"test_tip")]];
    [st addArrangedSubview:[self chk:S(@"verbose") key:@"verbose_log" on:YES tip:S(@"verbose_tip")]];
    [st addArrangedSubview:[self sep]];

    NSButton *saveBtn = [self btn:S(@"save") action:@selector(doSave:)];
    [st addArrangedSubview:saveBtn];

    // ── RIGHT column: Fight settings ──
    NSStackView *rt = [NSStackView new];
    rt.orientation = NSUserInterfaceLayoutOrientationVertical;
    rt.alignment = NSLayoutAttributeLeading;
    rt.spacing = 7;
    rt.edgeInsets = NSEdgeInsetsMake(6, 14, 20, 28);

    [rt addArrangedSubview:[self sep]];

    // Fish Force
    NSButton *testFishBtn = [self btn:S(@"test_fish") action:@selector(testFish:)];
    testFishBtn.font = [NSFont systemFontOfSize:10];
    NSStackView *fishHeader = [NSStackView stackViewWithViews:@[
        makeLabel(S(@"fish_t"), 11, FP_ACCENT, YES), testFishBtn]];
    fishHeader.spacing = 8;
    [rt addArrangedSubview:fishHeader];
    [rt addArrangedSubview:makeLabel(S(@"fish_d"), 10, FP_DIM, NO)];
    [rt addArrangedSubview:[self sl:S(@"heavy") key:@"fish_left_motor" val:5 tip:S(@"heavy_tip")]];
    [rt addArrangedSubview:[self sl:S(@"light") key:@"fish_right_motor" val:10 tip:S(@"light_tip")]];
    [rt addArrangedSubview:[self sl:S(@"ltrig") key:@"fish_left_trigger" val:0 tip:S(@"trig_tip")]];
    [rt addArrangedSubview:[self sl:S(@"rtrig") key:@"fish_right_trigger" val:5 tip:S(@"trig_tip")]];

    [rt addArrangedSubview:[self sep]];

    // Rod Force
    NSButton *testRodBtn = [self btn:S(@"test_rod") action:@selector(testRod:)];
    testRodBtn.font = [NSFont systemFontOfSize:10];
    NSStackView *rodHeader = [NSStackView stackViewWithViews:@[
        makeLabel(S(@"rod_t"), 11, FP_ACCENT, YES), testRodBtn]];
    rodHeader.spacing = 8;
    [rt addArrangedSubview:rodHeader];
    [rt addArrangedSubview:makeLabel(S(@"rod_d"), 10, FP_DIM, NO)];
    [rt addArrangedSubview:[self sl:S(@"heavy") key:@"rod_left_motor" val:20 tip:S(@"heavy_tip")]];
    [rt addArrangedSubview:[self sl:S(@"light") key:@"rod_right_motor" val:40 tip:S(@"light_tip")]];
    [rt addArrangedSubview:[self sl:S(@"ltrig") key:@"rod_left_trigger" val:10 tip:S(@"trig_tip")]];
    [rt addArrangedSubview:[self sl:S(@"rtrig") key:@"rod_right_trigger" val:20 tip:S(@"trig_tip")]];

    [rt addArrangedSubview:[self sep]];

    // Line Tension
    NSButton *testTensBtn = [self btn:S(@"test_tens") action:@selector(testTension:)];
    testTensBtn.font = [NSFont systemFontOfSize:10];
    NSStackView *tensHeader = [NSStackView stackViewWithViews:@[
        makeLabel(S(@"tens_t"), 11, FP_ACCENT, YES), testTensBtn]];
    tensHeader.spacing = 8;
    [rt addArrangedSubview:tensHeader];
    [rt addArrangedSubview:makeLabel(S(@"tens_d"), 10, FP_DIM, NO)];
    [rt addArrangedSubview:[self sl:S(@"heavy") key:@"tension_left_motor" val:10 tip:S(@"heavy_tip")]];
    [rt addArrangedSubview:[self sl:S(@"light") key:@"tension_right_motor" val:20 tip:S(@"light_tip")]];
    [rt addArrangedSubview:[self sl:S(@"ltrig") key:@"tension_left_trigger" val:5 tip:S(@"trig_tip")]];
    [rt addArrangedSubview:[self sl:S(@"rtrig") key:@"tension_right_trigger" val:10 tip:S(@"trig_tip")]];

    [rt addArrangedSubview:[self sep]];

    // Haptic Pulse
    NSButton *testPulseBtn = [self btn:S(@"test_pulse") action:@selector(testPulse:)];
    testPulseBtn.font = [NSFont systemFontOfSize:10];
    NSStackView *pulseHeader = [NSStackView stackViewWithViews:@[
        makeLabel(S(@"pulse_t"), 11, FP_ACCENT, YES), testPulseBtn]];
    pulseHeader.spacing = 8;
    [rt addArrangedSubview:pulseHeader];
    [rt addArrangedSubview:makeLabel(S(@"pulse_d"), 10, FP_DIM, NO)];
    [rt addArrangedSubview:[self sl:S(@"heavy") key:@"pulse_left_motor" val:60 tip:S(@"heavy_tip")]];
    [rt addArrangedSubview:[self sl:S(@"light") key:@"pulse_right_motor" val:30 tip:S(@"light_tip")]];
    [rt addArrangedSubview:[self sl:S(@"ltrig") key:@"pulse_left_trigger" val:20 tip:S(@"trig_tip")]];
    [rt addArrangedSubview:[self sl:S(@"rtrig") key:@"pulse_right_trigger" val:30 tip:S(@"trig_tip")]];

    // ── Place columns side by side ──
    NSSize leftFit = [st fittingSize];
    NSSize rightFit = [rt fittingSize];
    CGFloat colHeight = leftFit.height > rightFit.height ? leftFit.height : rightFit.height;

    st.frame = NSMakeRect(0, y, colW, colHeight);
    rt.frame = NSMakeRect(colW, y, colW, colHeight);

    NSView *divider = [[NSView alloc] initWithFrame:NSMakeRect(colW, y + 10, 1, colHeight - 20)];
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = [FP_SEP CGColor];

    [doc addSubview:st];
    [doc addSubview:divider];
    [doc addSubview:rt];
    y += colHeight;

    doc.frame = NSMakeRect(0, 0, W, y);

    // Resize window to fit content
    NSRect frame = self.window.frame;
    CGFloat newH = y < 900 ? y : 900;
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
    [s.widthAnchor constraintEqualToConstant:175].active = YES;

    NSTextField *v = makeLabel([NSString stringWithFormat:@"%d%%", val], 12, FP_DIM, NO);
    v.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    [v.widthAnchor constraintEqualToConstant:40].active = YES;

    NSButton *tb = [NSButton buttonWithTitle:@"\u25B6" target:self action:@selector(testMotor:)];
    tb.bordered = NO;
    tb.contentTintColor = FP_ACCENT;
    tb.font = [NSFont systemFontOfSize:10];
    tb.toolTip = tip;
    [self.testBtnToKey setObject:key forKey:tb];

    self.sliders[key] = s;
    self.sliderLabels[key] = v;
    [self.sliderToKey setObject:key forKey:s];

    NSStackView *row = [NSStackView stackViewWithViews:@[lbl, s, v, tb]];
    row.spacing = 6;
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
    [c appendString:@"\n# --- Fight: Fish Force (background hum from hooked fish) ---\n"];
    [c appendFormat:@"fish_left_motor = %d\n", [self iv:@"fish_left_motor"]];
    [c appendFormat:@"fish_right_motor = %d\n", [self iv:@"fish_right_motor"]];
    [c appendFormat:@"fish_left_trigger = %d\n", [self iv:@"fish_left_trigger"]];
    [c appendFormat:@"fish_right_trigger = %d\n", [self iv:@"fish_right_trigger"]];
    [c appendString:@"\n# --- Fight: Rod Force (dynamic from rod strain) ---\n"];
    [c appendFormat:@"rod_left_motor = %d\n", [self iv:@"rod_left_motor"]];
    [c appendFormat:@"rod_right_motor = %d\n", [self iv:@"rod_right_motor"]];
    [c appendFormat:@"rod_left_trigger = %d\n", [self iv:@"rod_left_trigger"]];
    [c appendFormat:@"rod_right_trigger = %d\n", [self iv:@"rod_right_trigger"]];
    [c appendString:@"\n# --- Fight: Line Tension ---\n"];
    [c appendFormat:@"tension_left_motor = %d\n", [self iv:@"tension_left_motor"]];
    [c appendFormat:@"tension_right_motor = %d\n", [self iv:@"tension_right_motor"]];
    [c appendFormat:@"tension_left_trigger = %d\n", [self iv:@"tension_left_trigger"]];
    [c appendFormat:@"tension_right_trigger = %d\n", [self iv:@"tension_right_trigger"]];
    [c appendString:@"\n# --- Fight: Haptic Pulse (sharp hit from game) ---\n"];
    [c appendFormat:@"pulse_left_motor = %d\n", [self iv:@"pulse_left_motor"]];
    [c appendFormat:@"pulse_right_motor = %d\n", [self iv:@"pulse_right_motor"]];
    [c appendFormat:@"pulse_left_trigger = %d\n", [self iv:@"pulse_left_trigger"]];
    [c appendFormat:@"pulse_right_trigger = %d\n", [self iv:@"pulse_right_trigger"]];
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

// ── Controller status ──
- (void)hidStatusChanged:(NSNotification *)n { [self refreshCtrlStatus]; }

- (void)refreshCtrlStatus {
    if (!self.ctrlLabel) return;
    if (g_hid_ready) {
        self.ctrlLabel.stringValue = [NSString stringWithFormat:@"\u25CF %@", S(@"ctrl_on")];
        self.ctrlLabel.textColor = FP_ACCENT;
    } else {
        self.ctrlLabel.stringValue = [NSString stringWithFormat:@"\u25CB %@", S(@"ctrl_off")];
        self.ctrlLabel.textColor = FP_WARN;
    }
}

// ── Vibration tests ──
- (uint8_t)motorVal:(NSString *)key { return (uint8_t)([self iv:key] * 255 / 100); }

- (void)rumblePulse:(uint8_t)lt rt:(uint8_t)rt left:(uint8_t)left right:(uint8_t)right ms:(int)ms {
    if (!g_hid_ready) { [self alert:S(@"no_ctrl_t") info:S(@"no_ctrl_i")]; return; }
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        send_hid_rumble(lt, rt, left, right);
        usleep(ms * 1000);
        send_hid_rumble(0, 0, 0, 0);
    });
}

- (void)testBite:(id)sender {
    if (!g_hid_ready) { [self alert:S(@"no_ctrl_t") info:S(@"no_ctrl_i")]; return; }
    uint8_t L = [self motorVal:@"bite_left_motor"];
    uint8_t R = [self motorVal:@"bite_right_motor"];
    uint8_t LT = [self motorVal:@"bite_left_trigger"];
    uint8_t RT = [self motorVal:@"bite_right_trigger"];
    BOOL dbl = self.checks[@"bite_double_tap"].state == NSControlStateValueOn;
    uint8_t str2 = [self motorVal:@"bite_double_tap_strength"];
    uint8_t L2 = (uint8_t)(L * str2 / 255);
    uint8_t R2 = (uint8_t)(R * str2 / 255);

    dispatch_async(dispatch_get_global_queue(0,0), ^{
        send_hid_rumble(LT, RT, L, R);
        usleep(400000);
        send_hid_rumble(0, 0, 0, 0);
        if (dbl) {
            usleep(100000);
            send_hid_rumble(LT, RT, L2, R2);
            usleep(300000);
            send_hid_rumble(0, 0, 0, 0);
        }
    });
}

- (void)testReel:(id)sender {
    if (!g_hid_ready) { [self alert:S(@"no_ctrl_t") info:S(@"no_ctrl_i")]; return; }
    uint8_t L = [self motorVal:@"reel_left_motor"];
    uint8_t R = [self motorVal:@"reel_right_motor"];
    uint8_t LT = [self motorVal:@"reel_left_trigger"];
    uint8_t RT = [self motorVal:@"reel_right_trigger"];
    // Simulate tuk-tuk pulse pattern (4 clicks, ~6Hz)
    dispatch_async(dispatch_get_global_queue(0,0), ^{
        for (int i = 0; i < 4; i++) {
            send_hid_rumble(LT, RT, L, R);
            usleep(80000);
            send_hid_rumble(0, 0, 0, 0);
            usleep(70000);
        }
    });
}

- (void)testFish:(id)sender {
    [self rumblePulse:[self motorVal:@"fish_left_trigger"]
                   rt:[self motorVal:@"fish_right_trigger"]
                 left:[self motorVal:@"fish_left_motor"]
                right:[self motorVal:@"fish_right_motor"] ms:1000];
}

- (void)testRod:(id)sender {
    [self rumblePulse:[self motorVal:@"rod_left_trigger"]
                   rt:[self motorVal:@"rod_right_trigger"]
                 left:[self motorVal:@"rod_left_motor"]
                right:[self motorVal:@"rod_right_motor"] ms:1000];
}

- (void)testTension:(id)sender {
    [self rumblePulse:[self motorVal:@"tension_left_trigger"]
                   rt:[self motorVal:@"tension_right_trigger"]
                 left:[self motorVal:@"tension_left_motor"]
                right:[self motorVal:@"tension_right_motor"] ms:1000];
}

- (void)testPulse:(id)sender {
    [self rumblePulse:[self motorVal:@"pulse_left_trigger"]
                   rt:[self motorVal:@"pulse_right_trigger"]
                 left:[self motorVal:@"pulse_left_motor"]
                right:[self motorVal:@"pulse_right_motor"] ms:400];
}

- (void)testMotor:(NSButton *)sender {
    NSString *key = [self.testBtnToKey objectForKey:sender];
    if (!key) return;
    uint8_t val = [self motorVal:key];
    uint8_t lt=0, rt=0, left=0, right=0;
    if ([key hasSuffix:@"left_motor"])        left = val;
    else if ([key hasSuffix:@"right_motor"])  right = val;
    else if ([key hasSuffix:@"left_trigger"]) lt = val;
    else if ([key hasSuffix:@"right_trigger"])rt = val;
    else if ([key hasSuffix:@"double_tap_strength"]) { left = val; right = val; }
    [self rumblePulse:lt rt:rt left:left right:right ms:400];
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
