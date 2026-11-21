# Host unit tests for the HCG Animation Center pure C core (no iOS SDK needed).
CC ?= cc
CFLAGS ?= -std=c11 -O1 -g -Wall -Wextra -Werror -Wshadow -Wdouble-promotion -Wno-unused-parameter
SANITIZE ?= -fsanitize=address,undefined -fno-sanitize-recover=all
# One build directory per compiler, so switching CC really recompiles.
BUILD ?= build/$(notdir $(firstword $(CC)))
KIT := ../HCGBackgroundKit/Sources/HCGBackgroundKit
CORE := $(KIT)/HCGBackgroundCore.c ../src/HACPolicy.c
HEADERS := $(KIT)/include/HCGBackgroundCore.h ../src/HACPolicy.h

.PHONY: test schema compat deb-format clean
test: $(BUILD)/test_core
	$(abspath $(BUILD))/test_core

$(BUILD)/test_core: test_core.c $(CORE) $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SANITIZE) -I$(KIT)/include -I../src -o $@ test_core.c $(CORE) -lm

# The preset schema, the example presets and the code's constants agree.
schema:
	python3 -I test_schema.py

# Kit 1.0's C code is unchanged (the Mac app vendors it by checksum); 1.1 only appends.
compat:
	python3 -I test_core_compat.py

# Packaging regression check (gzip-only .deb members). Python standard library.
deb-format:
	python3 -I test_deb_format.py

clean:
	rm -rf $(BUILD)
