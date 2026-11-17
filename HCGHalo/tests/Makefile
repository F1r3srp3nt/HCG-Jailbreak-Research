# Host unit tests for the HCG Halo pure C core (no iOS SDK needed).
CC ?= cc
CFLAGS ?= -std=c11 -O1 -g -Wall -Wextra -Werror -Wshadow -Wdouble-promotion -Wno-unused-parameter
SANITIZE ?= -fsanitize=address,undefined -fno-sanitize-recover=all
BUILD ?= build
CORE := ../src/HaloGeometry.c ../src/HaloConfig.c ../src/HaloProfiles.c ../src/HaloProfiles.generated.c
HEADERS := ../src/HaloGeometry.h ../src/HaloConfig.h ../src/HaloProfiles.h

.PHONY: test generated deb-format clean
test: $(BUILD)/test_core
	$(abspath $(BUILD))/test_core

$(BUILD)/test_core: test_core.c $(CORE) $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SANITIZE) -o $@ test_core.c $(CORE) -lm

# Generated files (profile table, Root.plist) match their sources.
generated:
	python3 -I ../scripts/generate.py --check

# Packaging regression check (gzip-only .deb members). Python standard library.
deb-format:
	python3 -I test_deb_format.py

clean:
	rm -rf $(BUILD)
