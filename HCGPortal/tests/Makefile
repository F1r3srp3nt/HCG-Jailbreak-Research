# Host unit tests for the HCG Portal pure C core (no iOS SDK needed).
CC ?= cc
CFLAGS ?= -std=c11 -O1 -g -Wall -Wextra -Werror -Wshadow -Wdouble-promotion -Wno-unused-parameter
SANITIZE ?= -fsanitize=address,undefined -fno-sanitize-recover=all
# One build directory per compiler, so switching CC really recompiles.
BUILD ?= build/$(notdir $(firstword $(CC)))
CORE := ../src/PortalCore.c
HEADERS := ../src/PortalCore.h

.PHONY: test deb-format clean
test: $(BUILD)/test_core
	$(abspath $(BUILD))/test_core

$(BUILD)/test_core: test_core.c $(CORE) $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SANITIZE) -D_DEFAULT_SOURCE -I../src -o $@ test_core.c $(CORE) -lm

# Packaging regression check (gzip-only .deb members). Python standard library.
deb-format:
	python3 -I test_deb_format.py

clean:
	rm -rf build
