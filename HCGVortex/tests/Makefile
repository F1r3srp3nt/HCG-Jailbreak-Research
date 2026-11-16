# Host unit tests for the HCG Vortex math core (no iOS SDK needed).
CC ?= cc
CFLAGS ?= -std=c11 -O1 -Wall -Wextra -Werror
SANITIZE ?= -fsanitize=address,undefined
BUILD := build

.PHONY: test compat compat-gnustep clean
test: $(BUILD)/test_math
	$(abspath $(BUILD))/test_math

# Compatibility gate tests: need an Objective-C runtime + Foundation (macOS).
compat: $(BUILD)/test_compat
	$(abspath $(BUILD))/test_compat

$(BUILD)/test_compat: test_compat.m ../src/VortexCompatibility.m ../src/VortexCompatibility.h
	@mkdir -p $(BUILD)
	$(CC) -fno-objc-arc -Wall -Wextra -Werror -Wno-unused-parameter $(SANITIZE) -framework Foundation -o $@ test_compat.m ../src/VortexCompatibility.m

# Same tests on Linux with GNUstep (CI Linux check): apt-get install gnustep-devel
GNUSTEP_OBJC_FLAGS = $(shell gnustep-config --objc-flags 2>/dev/null)
GNUSTEP_BASE_LIBS = $(shell gnustep-config --base-libs 2>/dev/null)
compat-gnustep: test_compat.m ../src/VortexCompatibility.m ../src/VortexCompatibility.h
	@mkdir -p $(BUILD)
	gcc -std=gnu11 $(GNUSTEP_OBJC_FLAGS) -Wall -Wextra -Werror -Wno-unused-parameter -Wno-expansion-to-defined -Wno-cast-function-type \
		-o $(BUILD)/test_compat_gnustep test_compat.m ../src/VortexCompatibility.m $(GNUSTEP_BASE_LIBS)
	$(abspath $(BUILD))/test_compat_gnustep

$(BUILD)/test_math: test_math.c ../src/VortexMath.c ../src/VortexMath.h ../src/VortexTypes.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SANITIZE) -o $@ test_math.c ../src/VortexMath.c -lm

clean:
	rm -rf $(BUILD)
