# Host build for the DSP-port stage tests (plain gcc, no ESP-IDF).
# Each stage test loads its input vector, runs the C, and diffs vs the
# Python golden output in test_vectors/.
#
#   make test    build + run every stage test
#   make clean

CC      ?= gcc
CFLAGS  ?= -std=c99 -O2 -Wall -Wextra -Wno-unused-parameter
LDFLAGS ?= -lm

BUILD   := build
SRC     := src
TEST    := test
VECDIR  := test_vectors

# One entry per ported stage: <name>_test built from test/<name>_test.c +
# src/<name>.c + the shared vec_io.c.
STAGES  := nulldrop resample frontend pairs cscr waveform bandpass

TESTS   := $(addprefix $(BUILD)/,$(addsuffix _test,$(STAGES))) $(BUILD)/estimator_test

.PHONY: test clean
test: $(TESTS)
	@echo "=== running dsp_port stage tests ==="
	@fail=0; for t in $(TESTS); do \
		./$$t $(VECDIR) || fail=1; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== all stage tests PASS ==="; else echo "=== some stage tests FAILED ==="; exit 1; fi

# estimator_test needs two src files (estimator + fft), so give it its own rule
# ahead of the generic single-source pattern below.
$(BUILD)/estimator_test: $(TEST)/estimator_test.c $(SRC)/dsp_estimator.c $(SRC)/dsp_fft.c $(TEST)/vec_io.c | $(BUILD)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

$(BUILD)/%_test: $(TEST)/%_test.c $(SRC)/%.c $(TEST)/vec_io.c | $(BUILD)
	$(CC) $(CFLAGS) $^ -o $@ $(LDFLAGS)

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
