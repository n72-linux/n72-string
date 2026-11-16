/* SPDX-License-Identifier: MIT */
/*
 * memset for ARMv6 (ARM1176JZF-S: the iPod touch 2G's S5L8720), ARM state.
 *
 *	void *memset(void *dst, int c, size_t n)
 *
 * musl has no memset for ARM in assembly and its C version stores a word
 * at a time. Here: bytes up to a word boundary, then 32 bytes per store
 * (one STM of eight registers), then eight bytes per store, then the last
 * word and bytes. Fewer than 16 bytes go a byte at a time.
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
	and	r1, r1, #255
	mov	ip, r0			@ ip writes; r0 is returned as it came
	cmp	r2, #16
	orr	r1, r1, r1, lsl #8
	orr	r1, r1, r1, lsl #16
	blo	.Lbytes

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
	mov	r3, r1
	cmp	r2, #64
	blo	.Lwords

	@ 32 bytes a store
	push	{r4, r5, r6, r7, r8, lr}
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

.Lbytes:
	@ 0 .. 15 bytes, any alignment
	subs	r2, r2, #1
	bxlo	lr
5:	strb	r1, [ip], #1
	subs	r2, r2, #1
	bhs	5b
	bx	lr
	.size	NAME, . - NAME
