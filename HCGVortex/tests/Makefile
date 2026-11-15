# Host unit tests for the HCG Vortex math core (no iOS SDK needed).
CC ?= cc
CFLAGS ?= -std=c11 -O1 -Wall -Wextra -Werror
SANITIZE ?= -fsanitize=address,undefined
BUILD := build

.PHONY: test clean
test: $(BUILD)/test_math
	$(abspath $(BUILD))/test_math

$(BUILD)/test_math: test_math.c ../src/VortexMath.c ../src/VortexMath.h ../src/VortexTypes.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(SANITIZE) -o $@ test_math.c ../src/VortexMath.c -lm

clean:
	rm -rf $(BUILD)
