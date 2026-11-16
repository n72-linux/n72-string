/* SPDX-License-Identifier: MIT */
/*
 * n72-string: memset and memcmp against plain references.
 *
 * memset: every start alignment 0..63 x every length 0..600, and large
 * lengths, with several fill values: the bytes, the bytes around (never
 * touched) and the return value. The block ends at an unmapped page, so a
 * store past the end faults.
 *
 * memcmp: every alignment 0..7 of both blocks x every length 0..600, and
 * large lengths: equal blocks, and a difference at every place (short
 * blocks) or at chosen places (long ones), both ways round and with bytes
 * above 0x7f (the comparison is of unsigned chars); only the sign of the
 * result counts. Both blocks end at an unmapped page, so a load past the
 * end faults.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

void *n72_memset(void *dst, int c, size_t n);
int n72_memcmp(const void *l, const void *r, size_t n);

static long fails, checks;
#define FAIL(...) do { if (fails++ < 20) { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* size bytes ending at an unmapped page (the block starts at ret) */
static uint8_t *guarded(size_t size, uint8_t **base)
{
	size_t page = (size_t)sysconf(_SC_PAGESIZE), len = (size + page - 1) / page * page;
	uint8_t *m = mmap(NULL, len + page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

	if (m == MAP_FAILED || mprotect(m + len, page, PROT_NONE)) {
		perror("mmap");
		exit(2);
	}
	*base = m;
	return m + len - size;
}

static int sign(int v) { return v < 0 ? -1 : v > 0; }

static int ref_memcmp(const uint8_t *l, const uint8_t *r, size_t n)
{
	size_t i;

	for (i = 0; i < n; i++)
		if (l[i] != r[i])
			return l[i] < r[i] ? -1 : 1;
	return 0;
}

static void test_memset_one(uint8_t *area, size_t area_size, size_t off_from_end, size_t n, int c)
{
	/* the block [p, p + n) ends off_from_end bytes before the unmapped page */
	uint8_t *p = area + area_size - off_from_end - n, *q;
	size_t i, lead = (size_t)(p - area) < 80 ? (size_t)(p - area) : 80;
	void *ret;

	memset(p - lead, 0x5a, lead + n + off_from_end);
	ret = n72_memset(p, c, n);
	checks++;
	if (ret != p)
		FAIL("memset(%p, %#x, %zu) returned %p", (void *)p, c, n, ret);
	for (q = p - lead; q < p; q++)
		if (*q != 0x5a) {
			FAIL("memset(%p, %#x, %zu) wrote %zu bytes before the block", (void *)p, c, n, (size_t)(p - q));
			break;
		}
	for (i = 0; i < n; i++)
		if (p[i] != (uint8_t)c) {
			FAIL("memset(%p, %#x, %zu): byte %zu is %#x", (void *)p, c, n, i, p[i]);
			break;
		}
	for (i = 0; i < off_from_end; i++)
		if (p[n + i] != 0x5a) {
			FAIL("memset(%p, %#x, %zu) wrote %zu bytes past the block", (void *)p, c, n, i + 1);
			break;
		}
}

static void test_memset(void)
{
	static const int fills[] = { 0, 0xa5, 0xff, 0x1234, -1 };
	static const size_t big[] = { 601, 1000, 1023, 1024, 1025, 4095, 4096, 4097, 20000, 65536, 70001 };
	size_t size = 80000, a, n, f, b;
	uint8_t *base, *area = guarded(size, &base);

	for (f = 0; f < sizeof(fills) / sizeof(fills[0]); f++) {
		for (a = 0; a < 64; a++) {
			for (n = 0; n <= 600; n++) {
				/* start alignment a (the area's end is page aligned): end offset chosen for it */
				size_t off = (64 - (a + n) % 64) % 64;

				test_memset_one(area, size, off, n, fills[f]);
			}
			for (b = 0; b < sizeof(big) / sizeof(big[0]); b++)
				test_memset_one(area, size, (64 - (a + big[b]) % 64) % 64, big[b], fills[f]);
		}
		/* blocks that end exactly at the unmapped page */
		for (n = 0; n <= 600; n++)
			test_memset_one(area, size, 0, n, fills[f]);
	}
	printf("memset: %ld checks\n", checks);
}

static void test_memcmp_case(uint8_t *l, uint8_t *r, size_t n, const char *what)
{
	int got = n72_memcmp(l, r, n), want = ref_memcmp(l, r, n);

	checks++;
	if (sign(got) != sign(want))
		FAIL("memcmp(%p, %p, %zu) %s: %d, the reference says %d", (void *)l, (void *)r, n, what, got, want);
}

static void test_memcmp(void)
{
	static const size_t big[] = { 601, 1000, 1024, 4096, 4099, 20000, 65537 };
	static const uint8_t pairs[][2] = { { 1, 2 }, { 2, 1 }, { 0x7f, 0x80 }, { 0x80, 0x7f }, { 0, 0xff }, { 0xff, 0 }, { 0x10, 0x11 } };
	size_t size = 70000, al, ar, n, i, k, npairs = sizeof(pairs) / sizeof(pairs[0]);
	uint8_t *bl, *br, *L = guarded(size, &bl), *R = guarded(size, &br);
	long before = checks;
	uint32_t seed = 1;

	for (i = 0; i < size; i++) {
		seed = seed * 1664525u + 1013904223u;
		L[i] = R[i] = (uint8_t)(seed >> 24);
	}
	for (al = 0; al < 8; al++)
		for (ar = 0; ar < 8; ar++) {
			for (n = 0; n <= 600 + sizeof(big) / sizeof(big[0]); n++) {
				size_t len = n <= 600 ? n : big[n - 601];
				/* both blocks end at their unmapped pages when the alignment allows it:
				 * the start alignment is fixed by the end offset */
				uint8_t *l = L + size - len - (8 - (al + len) % 8) % 8;
				uint8_t *r = R + size - len - (8 - (ar + len) % 8) % 8;
				size_t step = len <= 64 ? 1 : len <= 600 ? 37 : len / 5 + 1;

				memcpy(r, l, len);
				test_memcmp_case(l, r, len, "equal blocks");
				for (i = 0; i < len; i += step) {
					uint8_t keep_l = l[i], keep_r = r[i];

					for (k = 0; k < npairs; k++) {
						l[i] = pairs[k][0];
						r[i] = pairs[k][1];
						test_memcmp_case(l, r, len, "one byte differs");
						if (i + 1 < len) {
							/* a later difference the other way round must not count */
							uint8_t kl = l[len - 1], kr = r[len - 1];

							l[len - 1] = pairs[k][1];
							r[len - 1] = pairs[k][0];
							test_memcmp_case(l, r, len, "two bytes differ");
							l[len - 1] = kl;
							r[len - 1] = kr;
						}
					}
					l[i] = keep_l;
					r[i] = keep_r;
				}
				if (len) {	/* the last byte alone */
					uint8_t kl = l[len - 1];

					l[len - 1] ^= 0x80;
					test_memcmp_case(l, r, len, "the last byte differs");
					l[len - 1] = kl;
				}
			}
		}
	/* blocks ending exactly at the unmapped pages, every length */
	for (n = 0; n <= 600; n++) {
		memcpy(R + size - n, L + size - n, n);
		test_memcmp_case(L + size - n, R + size - n, n, "equal, at the end of the mapping");
		if (n) {
			R[size - 1] ^= 1;
			test_memcmp_case(L + size - n, R + size - n, n, "last byte, at the end of the mapping");
			R[size - 1] ^= 1;
		}
	}
	printf("memcmp: %ld checks\n", checks - before);
}

int main(void)
{
	test_memset();
	test_memcmp();
	printf("%ld checks, %ld failures\n", checks, fails);
	return fails != 0;
}
