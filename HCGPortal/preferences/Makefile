# HCG Portal — Settings bundle (PreferenceLoader)
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS ?= arm64 arm64e
# Same pinned patched SDK and deployment target as the tweak (see ../Makefile).
TARGET ?= iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HCGPortalPrefs

# Same version and build ID as the tweak (exported by ../Makefile; recomputed
# when this directory is built on its own).
PORTAL_VERSION ?= $(subst ~,-,$(shell sed -n 's/^Version: *//p' $(CURDIR)/../control))
PORTAL_BUILD_ID ?= $(shell git -C $(CURDIR)/.. rev-parse --short=12 HEAD 2>/dev/null || echo unknown)$(shell git -C $(CURDIR)/.. status --porcelain -- . 2>/dev/null | grep -q . && echo -dirty)

# The validator, layout solver and renderer are shared with the tweak, so the
# Settings preview places and draws the portal exactly as SpringBoard does.
HCGPortalPrefs_FILES = \
	PortalRootListController.m \
	PortalPlacementController.m \
	PortalAppsController.m \
	PortalPreviewView.m \
	PortalTheme.m \
	../src/PortalPreferences.m \
	../src/PortalCompanions.m \
	../src/PortalView.m \
	../src/PortalCore.c
HCGPortalPrefs_FRAMEWORKS = UIKit QuartzCore CoreGraphics
HCGPortalPrefs_PRIVATE_FRAMEWORKS = Preferences
HCGPortalPrefs_INSTALL_PATH = /Library/PreferenceBundles
HCGPortalPrefs_CFLAGS = -fobjc-arc -fobjc-arc-exceptions -Wall -Wextra -Wno-unused-parameter -Werror \
	-DPORTAL_VERSION=\"$(PORTAL_VERSION)\" -DPORTAL_BUILD_ID=\"$(PORTAL_BUILD_ID)\" -I../src

include $(THEOS_MAKE_PATH)/bundle.mk
