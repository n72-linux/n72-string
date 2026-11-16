# SPDX-License-Identifier: MIT
# n72-string: memset and memcmp for the ARM1176 (musl has neither in assembly for ARM).
#   make            test and bench for the device (static, armv6 musl), in build/
#   make check      the exhaustive test under qemu-arm
CROSS  ?= armv6-alpine-linux-musleabihf-
CC      = $(CROSS)gcc
CFLAGS  = -O2 -mcpu=arm1176jzf-s -mfpu=vfpv2 -mfloat-abi=hard -Wall -Wextra -std=gnu11 -fno-builtin
QEMU   ?= qemu-arm -cpu arm1176

all: build/test build/bench

build/%.o: %.S
	@mkdir -p build
	$(CC) $(CFLAGS) -c $< -o $@

build/test: test.c build/memset.o build/memcmp.o
	$(CC) $(CFLAGS) -static -o $@ $^

build/bench: bench.c build/memset.o build/memcmp.o
	$(CC) $(CFLAGS) -static -o $@ $^

check: build/test
	$(QEMU) build/test

clean:
	rm -rf build

.PHONY: all check clean
