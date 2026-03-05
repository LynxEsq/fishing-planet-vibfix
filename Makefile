# Fishing Planet Vibration Fix — Build
ARCH = arm64
MIN_MACOS = 13.0
CFLAGS = -arch $(ARCH) -mmacosx-version-min=$(MIN_MACOS) -Wno-deprecated-declarations

.PHONY: all clean install uninstall

all: build/vibration_fix.dylib build/launch VibFix.app

VIBFIX_SRC = src/vibfix_config.c src/vibfix_hooks.c src/vibfix_output.m src/vibration_fix.m

build/vibration_fix.dylib: $(VIBFIX_SRC) src/vibfix.h
	mkdir -p build
	clang -dynamiclib -o $@ $(VIBFIX_SRC) \
		-framework Foundation -framework GameController -framework IOKit \
		$(CFLAGS)
	codesign -fs - $@

build/launch: src/launch_wrapper.c
	mkdir -p build
	clang -o $@ $< $(CFLAGS)
	codesign -fs - $@

VibFix.app: src/VibFixApp.m assets/AppIcon.icns
	mkdir -p VibFix.app/Contents/MacOS VibFix.app/Contents/Resources
	clang -o VibFix.app/Contents/MacOS/VibFix $< -framework Cocoa -framework QuartzCore -framework IOKit $(CFLAGS)
	cp assets/AppIcon.icns VibFix.app/Contents/Resources/AppIcon.icns
	/usr/libexec/PlistBuddy \
		-c "Clear dict" \
		-c "Add :CFBundleExecutable string VibFix" \
		-c "Add :CFBundleName string VibFix" \
		-c "Add :CFBundleIdentifier string com.vibfix.app" \
		-c "Add :CFBundleVersion string 9.0" \
		-c "Add :CFBundleIconFile string AppIcon" \
		-c "Add :NSHighResolutionCapable bool true" \
		-c "Add :LSMinimumSystemVersion string 13.0" \
		VibFix.app/Contents/Info.plist
	codesign -fs - VibFix.app

clean:
	rm -f build/vibration_fix.dylib build/launch
	rm -rf VibFix.app

install: all
	@./scripts/install.sh

uninstall:
	@./scripts/uninstall.sh
