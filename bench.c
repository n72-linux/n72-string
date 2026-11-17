/* SPDX-License-Identifier: MIT */
/* n72-string: the routines against the C library's on the machine it runs on (the iPod: musl's). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

void *n72_memset(void *dst, int c, size_t n);
int n72_memcmp(const void *l, const void *r, size_t n);

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* through pointers the compiler cannot see through, so that neither call is replaced or dropped */
static void *(*volatile set_fn[2])(void *, int, size_t) = { memset, n72_memset };
static int (*volatile cmp_fn[2])(const void *, const void *, size_t) = { memcmp, n72_memcmp };
static volatile int sink;

/* read every cache line of a block, so that it is in the data cache (this CPU allocates lines on reads only) */
static void touch(const uint8_t *p, size_t n)
{
	size_t i;
	unsigned acc = 0;

	for (i = 0; i < n; i += 32)
		acc += p[i];
	sink = (int)acc;
}

int main(void)
{
	static const size_t sizes[] = { 1, 3, 4, 7, 8, 12, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 16384, 65536, 262144 };
	static const size_t aligns[] = { 0, 1, 3 };
	/* on a cache line, so that "+align" is the block's place within a line whatever the link put before it */
	static uint8_t a[262144 + 64] __attribute__((aligned(64))), b[262144 + 64] __attribute__((aligned(64)));
	size_t off;
	size_t s, al, f, warm;

	/*
	 * memset. "cold": the block is only ever written, so no line of it is
	 * in the cache and every store goes to the bus (a z-buffer cleared
	 * before it is read). "warm": the block was read first and fits the
	 * cache (up to 8 KiB here), so the stores stay in it.
	 */
	printf("%-7s %-10s %5s %11s %11s %6s\n", "", "size+align", "", "libc ns", "n72 ns", "ratio");
	for (warm = 0; warm < 2; warm++)
		for (al = 0; al < sizeof(aligns) / sizeof(aligns[0]); al++)
			for (s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
				size_t n = sizes[s], reps = 30000000 / (n + 40), i;
				double t[2];

				if (warm && n > 8192)
					continue;
				if (reps < 200)
					reps = 200;
				for (f = 0; f < 2; f++) {
					void *(*fn)(void *, int, size_t) = set_fn[f];
					double t0;

					if (warm)
						touch(a, n + 64);
					t0 = now();
					for (i = 0; i < reps; i++)
						fn(a + aligns[al], (int)i, n);
					t[f] = (now() - t0) / reps * 1e9;
				}
				printf("memset  %6zu+%zu %5s %11.1f %11.1f %6.2f\n", n, aligns[al], warm ? "warm" : "cold",
				       t[0], t[1], t[0] / t[1]);
			}
	/*
	 * memset to memory that is not cached, by where the block starts
	 * within a cache line (32 bytes): the stores go to the bus as they
	 * are written, and how they fall on the lines decides the time.
	 */
	for (s = 0; s < 2; s++)
		for (off = 0; off < 32; off += off == 0 ? 1 : off == 1 ? 3 : 4) {
			size_t n = s ? 65536 : 4096, reps = 30000000 / (n + 40) / 2, i;
			double t[2];

			for (f = 0; f < 2; f++) {
				void *(*fn)(void *, int, size_t) = set_fn[f];
				double t0 = now();

				for (i = 0; i < reps; i++)
					fn(a + off, (int)i, n);
				t[f] = (now() - t0) / reps * 1e9;
			}
			printf("memset  %6zu@%-2zu %4s %11.1f %11.1f %6.2f\n", n, off, "line", t[0], t[1], t[0] / t[1]);
		}
	/*
	 * memcmp of equal blocks (the whole length is compared), and of blocks
	 * that differ in their first byte (the cost of the call itself).
	 */
	memset(a, 1, sizeof(a));
	memset(b, 1, sizeof(b));
	for (al = 0; al < sizeof(aligns) / sizeof(aligns[0]); al++)
		for (s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
			size_t n = sizes[s], reps = 20000000 / (n + 40), i;
			double t[2];

			if (reps < 100)
				reps = 100;
			for (f = 0; f < 2; f++) {
				int (*fn)(const void *, const void *, size_t) = cmp_fn[f];
				double t0 = now();
				int acc = 0;

				for (i = 0; i < reps; i++)
					acc += fn(a + aligns[al], b + (aligns[al] ? 2 : 0), n);
				sink = acc;
				t[f] = (now() - t0) / reps * 1e9;
				if (acc)
					printf("(memcmp of equal blocks was not 0)\n");
			}
			printf("memcmp  %6zu+%zu %5s %11.1f %11.1f %6.2f\n", n, aligns[al], "equal", t[0], t[1], t[0] / t[1]);
		}
	b[0] = 2;
	for (f = 0; f < 2; f++) {
		int (*fn)(const void *, const void *, size_t) = cmp_fn[f];
		size_t i, reps = 2000000;
		double t0 = now();
		int acc = 0;

		for (i = 0; i < reps; i++)
			acc += fn(a, b, 256);
		sink = acc;
		printf("memcmp  first byte differs, %s: %.1f ns\n", f ? "n72" : "libc", (now() - t0) / reps * 1e9);
	}
	for (f = 0; f < 2; f++) {
		int (*fn)(const void *, const void *, size_t) = cmp_fn[f];
		size_t i, reps = 2000000;
		double t0 = now();
		int acc = 0;

		for (i = 0; i < reps; i++)
			acc += fn(a, b, 3);
		sink = acc;
		printf("memcmp  first byte differs, 3 bytes, %s: %.1f ns\n", f ? "n72" : "libc", (now() - t0) / reps * 1e9);
	}
	return 0;
}
