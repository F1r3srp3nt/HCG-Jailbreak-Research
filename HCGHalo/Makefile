# HCG Halo — Hakmi Capital Group
# Rootless Theos project. See docs/BUILD.md.
#
#   make package FINALPACKAGE=1                       # macOS + Xcode (canonical)
#   make package FINALPACKAGE=1 HALO_ABI_CONVERT=1 ALLEMANDE=/path/to/allemande
#                                                     # Linux toolchain (test builds only)
#
# Prefer scripts/build.sh, which checks the environment and validates output.
# Toolchain choices follow HCG Vortex (HCGVortex/docs/BUILD.md on its branch):
# same pinned Theos, same patched SDK, same gzip packaging.

THEOS_PACKAGE_SCHEME ?= rootless
ARCHS ?= arm64 arm64e
# Patched iPhoneOS16.5.sdk from theos/sdks (scripts/install-sdk.sh) on every
# platform: Xcode's public SDK lacks the private Preferences.framework stub the
# Settings bundle links. On macOS the compiler is still Xcode's clang, so
# arm64e keeps the native ABI. Deploy to iOS 15.0, the rootless floor; every
# API used is available there (docs/COMPATIBILITY.md).
TARGET ?= iphone:clang:16.5:15.0

# Package format: gzip for every member (control.tar.gz, data.tar.gz), as HCG
# Vortex 0.1.0~beta2 adopted after its lzma beta failed to unpack on a phone.
# Fixed (:=) so FINALPACKAGE and local builds match CI; validate.sh section 3a
# rejects any other format.
THEOS_PLATFORM_DEB_COMPRESSION_TYPE := gzip
THEOS_PLATFORM_DEB_COMPRESSION_LEVEL := 9

include $(THEOS)/makefiles/common.mk

# Single source of truth for the version: ./control (0.1.0~beta1 is shown as
# 0.1.0-beta1). Build ID: the source commit, "-dirty" if HCGHalo/ has
# uncommitted changes. validate.sh checks both binaries carry them.
HALO_VERSION := $(subst ~,-,$(shell sed -n 's/^Version: *//p' $(THEOS_PROJECT_DIR)/control))
HALO_BUILD_ID := $(shell git -C $(THEOS_PROJECT_DIR) rev-parse --short=12 HEAD 2>/dev/null || echo unknown)$(shell git -C $(THEOS_PROJECT_DIR) status --porcelain -- . 2>/dev/null | grep -q . && echo -dirty)
export HALO_VERSION HALO_BUILD_ID
HALO_WARNINGS := -Wall -Wextra -Wno-unused-parameter -Werror
HALO_DEFINES := -DHALO_VERSION=\"$(HALO_VERSION)\" -DHALO_BUILD_ID=\"$(HALO_BUILD_ID)\"

TWEAK_NAME = HCGHalo

HCGHalo_FILES = \
	src/Tweak.x \
	src/HaloController.m \
	src/HaloOverlayView.m \
	src/HaloEdgeWindow.m \
	src/HaloScreen.m \
	src/HaloRenderer.m \
	src/HaloNexusDefinition.m \
	src/HaloNexusLink.m \
	src/HaloPanelBorderView.m \
	src/HaloPreferences.m \
	src/HaloLog.m \
	src/HaloGeometry.c \
	src/HaloConfig.c \
	src/HaloProfiles.c \
	src/HaloProfiles.generated.c

HCGHalo_CFLAGS = -fobjc-arc -fobjc-arc-exceptions $(HALO_WARNINGS) $(HALO_DEFINES)
HCGHalo_FRAMEWORKS = UIKit QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

# --- Optional arm64e ABI conversion (non-Xcode toolchains only) -------------
# Open-source toolchains emit the legacy arm64e ABI, which A12+ devices on
# iOS 15+ reject for system processes. For Linux test builds the STAGED
# Mach-O files are post-processed with allemande and re-signed (the approach
# HCG Vortex documents). Never enable this for Xcode builds.
ifeq ($(HALO_ABI_CONVERT),1)
ALLEMANDE ?= allemande
before-package::
	$(ECHO_NOTHING)set -e; \
	for f in $$(find "$(THEOS_STAGING_DIR)" -type f \( -name 'HCGHalo.dylib' -o -name 'HCGHaloPrefs' \)); do \
		echo "==> arm64e ABI conversion: $${f#$(THEOS_STAGING_DIR)}"; \
		"$(ALLEMANDE)" "$$f" "$$f.newabi" > "$$f.allemande.log" 2>&1 || { cat "$$f.allemande.log"; exit 1; }; \
		rm -f "$$f.allemande.log"; \
		mv "$$f.newabi" "$$f"; \
		"$(TARGET_CODESIGN)" -S "$$f"; \
	done$(ECHO_END)
endif

# Reference only: `make do` / `make install` push to a device over SSH.
# Never run as part of the build; device deployment needs explicit approval.
INSTALL_TARGET_PROCESSES = SpringBoard
