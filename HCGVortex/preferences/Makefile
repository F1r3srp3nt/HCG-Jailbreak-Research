# HCG Vortex — Settings bundle (PreferenceLoader)
THEOS_PACKAGE_SCHEME ?= rootless
ARCHS ?= arm64 arm64e
# Same pinned patched SDK as the tweak (see ../Makefile).
TARGET ?= iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = HCGVortexPrefs

# VortexPreferences.m + VortexMath.c are shared with the tweak so validation
# and defaults are identical in SpringBoard and in Settings.
HCGVortexPrefs_FILES = \
	VortexRootListController.m \
	VortexHeaderView.m \
	../src/VortexPreferences.m \
	../src/VortexMath.c
HCGVortexPrefs_FRAMEWORKS = UIKit QuartzCore
HCGVortexPrefs_PRIVATE_FRAMEWORKS = Preferences
HCGVortexPrefs_INSTALL_PATH = /Library/PreferenceBundles
HCGVortexPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Werror -DVORTEX_VERSION=\"0.1.0-alpha\" -I../src

include $(THEOS_MAKE_PATH)/bundle.mk
