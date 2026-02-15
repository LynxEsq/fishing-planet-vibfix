# Fishing Planet Vibration Fix — Build
ARCH = arm64
MIN_MACOS = 13.0
CFLAGS = -arch $(ARCH) -mmacosx-version-min=$(MIN_MACOS) -Wno-deprecated-declarations

GAME_APP = $(HOME)/Library/Application Support/Steam/steamapps/common/Fishing Planet/FishingPlanet.app
GAME_MACOS = $(GAME_APP)/Contents/MacOS

.PHONY: all clean install uninstall

all: vibration_fix.dylib launcher

vibration_fix.dylib: vibration_fix.m
	clang -dynamiclib -o $@ $< -framework Foundation -framework GameController $(CFLAGS)
	codesign -fs - $@

launcher: launcher.c
	clang -o $@ $< $(CFLAGS)
	codesign -fs - $@

clean:
	rm -f vibration_fix.dylib launcher

install: all
	@./install.sh

uninstall:
	@./uninstall.sh
