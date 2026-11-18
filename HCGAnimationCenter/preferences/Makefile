# HCG Animation Center — Settings bundle (PreferenceLoader)
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS ?= arm64 arm64e
# Same pinned patched SDK and deployment target as the tweak (see ../Makefile).
TARGET ?= iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HCGAnimationCenterPrefs

# Same version and build ID as the tweak (exported by ../Makefile; recomputed
# when this directory is built on its own).
HAC_VERSION ?= $(subst ~,-,$(shell sed -n 's/^Version: *//p' $(CURDIR)/../control))
HAC_BUILD_ID ?= $(shell git -C $(CURDIR)/.. rev-parse --short=12 HEAD 2>/dev/null || echo unknown)$(shell git -C $(CURDIR)/.. status --porcelain -- . 2>/dev/null | grep -q . && echo -dirty)
HAC_KIT := ../HCGBackgroundKit/Sources/HCGBackgroundKit

# The preset format, renderer and preferences validator are shared with the
# tweak, so the Settings preview draws exactly what SpringBoard draws and both
# agree on every value.
HCGAnimationCenterPrefs_FILES = \
	HACRootListController.m \
	HACLibraryViewController.m \
	HACEditorViewController.m \
	HACAIViewController.m \
	HACAIGeneration.m \
	HACLibrary.m \
	HACMediaImporter.m \
	HACTheme.m \
	../src/HACPreferences.m \
	../src/HACPolicy.c \
	$(HAC_KIT)/HCGBackgroundView.m \
	$(HAC_KIT)/HCGBackgroundPreset.m \
	$(HAC_KIT)/HCGBackgroundCore.c
HCGAnimationCenterPrefs_FRAMEWORKS = UIKit QuartzCore CoreGraphics AVFoundation CoreMedia CoreVideo ImageIO PhotosUI UniformTypeIdentifiers
HCGAnimationCenterPrefs_PRIVATE_FRAMEWORKS = Preferences
HCGAnimationCenterPrefs_INSTALL_PATH = /Library/PreferenceBundles
HCGAnimationCenterPrefs_CFLAGS = -fobjc-arc -fobjc-arc-exceptions -Wall -Wextra -Wno-unused-parameter -Werror \
	-DHAC_VERSION=\"$(HAC_VERSION)\" -DHAC_BUILD_ID=\"$(HAC_BUILD_ID)\" -I../src -I$(HAC_KIT)/include

include $(THEOS_MAKE_PATH)/bundle.mk
