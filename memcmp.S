/* SPDX-License-Identifier: MIT */
/*
 * memcmp for ARMv6 (ARM1176JZF-S), ARM state.
 *
 *	int memcmp(const void *l, const void *r, size_t n)
 *
 * musl's is a byte loop in C. Here: bytes until l is word aligned, then a
 * word of each per step (r may be unaligned: ARMv6 loads such words, and
 * Linux lets user space do it); the first words that differ are compared
 * byte-reversed, which orders them by their first byte in memory. No word
 * is read that is not wholly inside the n bytes. The result is the
 * difference of the first differing bytes (as unsigned char) in the byte
 * loops and 1 or -1 from the word loop: the sign is what the C standard
 * defines.
 *
 * Built as n72_memcmp for the tests and the benchmark; with
 * -DN72_STRING_LIBC the name is memcmp (musl: src/string/arm/memcmp.S).
 */
#ifdef N72_STRING_LIBC
#define NAME memcmp
#else
#define NAME n72_memcmp
#endif

	.syntax	unified
	.arch	armv6
	.arm
	.text
	.global	NAME
	.type	NAME, %function
	.p2align 5
NAME:
	push	{r4, lr}
	cmp	r2, #8
	blo	.Lbytes

	@ bytes until l is on a word boundary
	rsb	r3, r0, #0
	ands	r3, r3, #3
	beq	2f
	sub	r2, r2, r3
1:	ldrb	r4, [r0], #1
	ldrb	lr, [r1], #1
	subs	ip, r4, lr
	bne	.Lresult
	subs	r3, r3, #1
	bne	1b
2:
	@ words: at least five bytes are left here
	sub	r2, r2, #4
3:	ldr	r4, [r0], #4
	ldr	lr, [r1], #4
	cmp	r4, lr
	bne	.Lwords_differ
	subs	r2, r2, #4
	bhs	3b
	adds	r2, r2, #4		@ 0 .. 3 left
	beq	.Lequal
	b	4f

.Lbytes:
	cmp	r2, #0
	beq	.Lequal
4:	ldrb	r4, [r0], #1
	ldrb	lr, [r1], #1
	subs	ip, r4, lr
	bne	.Lresult
	subs	r2, r2, #1
	bne	4b
.Lequal:
	mov	r0, #0
	pop	{r4, pc}

.Lresult:
	mov	r0, ip
	pop	{r4, pc}

.Lwords_differ:
	rev	r4, r4
	rev	lr, lr
	cmp	r4, lr
	movhi	r0, #1
	mvnlo	r0, #0
	pop	{r4, pc}
	.size	NAME, . - NAME
