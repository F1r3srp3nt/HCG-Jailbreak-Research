# HCG Halo — Settings bundle (PreferenceLoader)
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS ?= arm64 arm64e
# Same pinned patched SDK and deployment target as the tweak (see ../Makefile).
TARGET ?= iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HCGHaloPrefs

# Same version and build ID as the tweak (exported by ../Makefile; recomputed
# when this directory is built on its own).
HALO_VERSION ?= $(subst ~,-,$(shell sed -n 's/^Version: *//p' $(CURDIR)/../control))
HALO_BUILD_ID ?= $(shell git -C $(CURDIR)/.. rev-parse --short=12 HEAD 2>/dev/null || echo unknown)$(shell git -C $(CURDIR)/.. status --porcelain -- . 2>/dev/null | grep -q . && echo -dirty)

# The validator, presets, geometry and renderer are shared with the tweak, so
# Settings and SpringBoard agree on every value, and the preview draws exactly
# what SpringBoard draws.
HCGHaloPrefs_FILES = \
	HaloRootListController.m \
	HaloHeaderView.m \
	HaloTheme.m \
	HaloColoursController.m \
	HaloPresetsController.m \
	HaloProfileController.m \
	HaloNexusBorderController.m \
	HaloAppPickerController.m \
	../src/HaloPreferences.m \
	../src/HaloScreen.m \
	../src/HaloRenderer.m \
	../src/HaloNexusDefinition.m \
	../src/HaloPanelBorderView.m \
	../src/HaloGeometry.c \
	../src/HaloConfig.c \
	../src/HaloProfiles.c \
	../src/HaloProfiles.generated.c
HCGHaloPrefs_FRAMEWORKS = UIKit QuartzCore CoreGraphics
HCGHaloPrefs_PRIVATE_FRAMEWORKS = Preferences
HCGHaloPrefs_INSTALL_PATH = /Library/PreferenceBundles
HCGHaloPrefs_CFLAGS = -fobjc-arc -fobjc-arc-exceptions -Wall -Wextra -Wno-unused-parameter -Werror \
	-DHALO_VERSION=\"$(HALO_VERSION)\" -DHALO_BUILD_ID=\"$(HALO_BUILD_ID)\" -I../src

include $(THEOS_MAKE_PATH)/bundle.mk
