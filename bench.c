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

int main(void)
{
	static const size_t sizes[] = { 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 16384, 65536, 262144 };
	static const size_t aligns[] = { 0, 1, 3 };
	static uint8_t a[262144 + 64], b[262144 + 64];
	size_t s, al, f;

	memset(a, 1, sizeof(a));
	memset(b, 1, sizeof(b));
	printf("%-8s %-6s %12s %12s %7s\n", "", "", "libc ns", "n72 ns", "ratio");
	for (al = 0; al < sizeof(aligns) / sizeof(aligns[0]); al++)
		for (s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
			size_t n = sizes[s], reps = 40000000 / (n + 40), i;
			double t[2];

			if (reps < 200)
				reps = 200;
			for (f = 0; f < 2; f++) {
				void *(*fn)(void *, int, size_t) = set_fn[f];
				double t0 = now();

				for (i = 0; i < reps; i++)
					fn(a + aligns[al], (int)i, n);
				t[f] = (now() - t0) / reps * 1e9;
			}
			printf("memset   %-6zu+%zu %10.1f %12.1f %7.2f\n", n, aligns[al], t[0], t[1], t[0] / t[1]);
		}
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
					acc += fn(a + aligns[al], b + (aligns[al] ? 2 : 0), n);	/* equal blocks: the whole length is compared */
				sink = acc;
				t[f] = (now() - t0) / reps * 1e9;
			}
			printf("memcmp   %-6zu+%zu %10.1f %12.1f %7.2f\n", n, aligns[al], t[0], t[1], t[0] / t[1]);
		}
	return 0;
}
