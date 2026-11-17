/* SPDX-License-Identifier: MIT */
/*
 * memset for ARMv6 (ARM1176JZF-S: the iPod touch 2G's S5L8720), ARM state.
 *
 *	void *memset(void *dst, int c, size_t n)
 *
 * musl has no memset for ARM in assembly and its C version stores a word
 * at a time. Here: bytes up to a word boundary, a word up to an 8-byte
 * boundary, then (64 bytes or more) pairs of words up to a cache line and
 * 32 bytes per store (one STM of eight registers), then eight bytes per
 * store, then the last word and bytes. 4 to 15 bytes are covered by up to
 * four word stores that overlap, from both ends; fewer leave at once.
 *
 * Why the alignment: this CPU does not bring a line into the cache on a
 * store, so a fill of memory that is not cached goes to the bus as it is
 * written. Measured on the iPod, per byte of a long fill, by where the
 * 32-byte stores start within a line: see README.md. A store that starts
 * on the line is one whole burst; the worst case, 4 bytes after it, takes
 * about two thirds longer.
 *
 * Built as n72_memset for the tests and the benchmark; with
 * -DN72_STRING_LIBC the name is memset (musl: src/string/arm/memset.S).
 */
#ifdef N72_STRING_LIBC
#define NAME memset
#else
#define NAME n72_memset
#endif

	.syntax	unified
	.arch	armv6
	.arm
	.text
	.global	NAME
	.type	NAME, %function
	.p2align 5
NAME:
	cmp	r2, #4
	and	r1, r1, #255
	blo	.Ltiny			@ 0 .. 3 bytes: the shortest way out
	mov	ip, r0			@ ip writes; r0 is returned as it came
	cmp	r2, #16
	orr	r1, r1, r1, lsl #8
	orr	r1, r1, r1, lsl #16
	blo	.Lshort

	@ up to three bytes to a word boundary
	rsb	r3, ip, #0
	ands	r3, r3, #3
	beq	1f
	sub	r2, r2, r3
	cmp	r3, #2
	strb	r1, [ip], #1
	strbge	r1, [ip], #1
	strbgt	r1, [ip], #1
1:
	@ a word to an 8-byte boundary
	tst	ip, #4
	strne	r1, [ip], #4
	subne	r2, r2, #4
	mov	r3, r1
	cmp	r2, #64
	blo	.Lwords

	@ pairs of words to a cache line boundary: 0, 8, 16 or 24 bytes
	push	{r4, r5, r6, r7, r8, lr}
	rsb	r4, ip, #0
	and	r4, r4, #24
	sub	r2, r2, r4		@ 40 or more left
	tst	r4, #8
	stmiane	ip!, {r1, r3}
	tst	r4, #16
	stmiane	ip!, {r1, r3}
	stmiane	ip!, {r1, r3}

	@ 32 bytes a store, each a whole line
	mov	r4, r1
	mov	r5, r1
	mov	r6, r1
	mov	r7, r1
	mov	r8, r1
	mov	lr, r1
	sub	r2, r2, #32
2:	stmia	ip!, {r1, r3, r4, r5, r6, r7, r8, lr}
	subs	r2, r2, #32
	bhs	2b
	add	r2, r2, #32		@ 0 .. 31 left
	pop	{r4, r5, r6, r7, r8, lr}

.Lwords:
	@ eight bytes a store
	subs	r2, r2, #8
	blo	4f
3:	stmia	ip!, {r1, r3}
	subs	r2, r2, #8
	bhs	3b
4:	@ r2 + 8 = 0 .. 7 left: bits 2, 1 and 0 say what
	tst	r2, #4
	strne	r1, [ip], #4
	tst	r2, #2
	strhne	r1, [ip], #2
	tst	r2, #1
	strbne	r1, [ip]
	bx	lr

.Lshort:
	@ 4 .. 15 bytes, any alignment: words that overlap, from both ends
	@ (ARMv6 stores a word at any address; Linux lets user space)
	add	r3, ip, r2		@ the end
	cmp	r2, #8
	str	r1, [ip]
	str	r1, [r3, #-4]
	bxlo	lr			@ 4 .. 7: two words cover it
	str	r1, [ip, #4]
	str	r1, [r3, #-8]
	bx	lr			@ 8 .. 15: four words cover it

.Ltiny:
	@ 0 .. 3 bytes
	cmp	r2, #1
	bxlo	lr
	strb	r1, [r0]
	bxeq	lr
	strb	r1, [r0, #1]
	cmp	r2, #3
	strbeq	r1, [r0, #2]
	bx	lr
	.size	NAME, . - NAME
