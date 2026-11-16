# HCG Vortex — Hakmi Capital Group
# Rootless Theos project. See docs/BUILD.md.
#
#   make package FINALPACKAGE=1                     # macOS + Xcode (canonical)
#   make package FINALPACKAGE=1 VORTEX_ABI_CONVERT=1 ALLEMANDE=/path/to/allemande
#                                                   # Linux toolchain (test builds)
#
# Prefer scripts/build.sh, which checks the environment and validates output.

THEOS_PACKAGE_SCHEME ?= rootless
ARCHS ?= arm64 arm64e
# Patched iPhoneOS16.5.sdk from theos/sdks (scripts/install-sdk.sh) on every
# platform: Xcode's public SDK lacks the private Preferences.framework stub the
# Settings bundle links. On macOS the compiler is still Xcode's clang, so
# arm64e keeps the native ABI. Deploy to iOS 15.0 (the rootless floor); the
# runtime compatibility gate decides whether hooks run.
TARGET ?= iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

VORTEX_VERSION := 0.1.0-alpha
VORTEX_WARNINGS := -Wall -Wextra -Wno-unused-parameter -Werror

TWEAK_NAME = HCGVortex

HCGVortex_FILES = \
	src/Tweak.x \
	src/VortexCore.m \
	src/VortexNavigation.m \
	src/VortexAnimationEngine.m \
	src/VortexPreferences.m \
	src/VortexMath.c \
	effects/VortexDirectionalEffect.m \
	effects/ReverseSlide.m \
	effects/VerticalRise.m \
	effects/VerticalFall.m \
	effects/VortexEffectRegistry.m

HCGVortex_CFLAGS = -fobjc-arc $(VORTEX_WARNINGS) -DVORTEX_VERSION=\"$(VORTEX_VERSION)\"
HCGVortex_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# --- Optional arm64e ABI conversion (non-Xcode toolchains only) -------------
# Theos: "it's only possible to build for the new [iOS 14+] arm64e ABI on
# macOS". Open-source toolchains emit the legacy ABI, which A12+ devices on
# iOS 15+ reject for system processes. For Linux test builds we post-process
# the STAGED Mach-O files with allemande and re-sign them. Never enable this
# for Xcode builds (they are already new-ABI; allemande would refuse them).
ifeq ($(VORTEX_ABI_CONVERT),1)
ALLEMANDE ?= allemande
before-package::
	$(ECHO_NOTHING)set -e; \
	for f in $$(find "$(THEOS_STAGING_DIR)" -type f \( -name 'HCGVortex.dylib' -o -name 'HCGVortexPrefs' \)); do \
		echo "==> arm64e ABI conversion: $${f#$(THEOS_STAGING_DIR)}"; \
		"$(ALLEMANDE)" "$$f" "$$f.newabi" > "$$f.allemande.log" 2>&1 || { cat "$$f.allemande.log"; exit 1; }; \
		rm -f "$$f.allemande.log"; \
		mv "$$f.newabi" "$$f"; \
		"$(TARGET_CODESIGN)" -S "$$f"; \
	done$(ECHO_END)
endif

# Reference only: `make do` / `make install` push to a device over SSH.
# Never run as part of the build; device deployment requires explicit
# authorisation (see docs/TESTING.md).
INSTALL_TARGET_PROCESSES = SpringBoard
