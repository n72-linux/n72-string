/* SPDX-License-Identifier: MIT */
/*
 * memcmp for ARMv6 (ARM1176JZF-S), ARM state.
 *
 *	int memcmp(const void *l, const void *r, size_t n)
 *
 * musl's is a byte loop in C. Here, from 4 bytes up, only words are
 * compared (ARMv6 loads a word at any address, and Linux lets user space
 * do it): the first word of each block as it lies, then words from l's
 * next word boundary, two a step, and at the end the last word of each
 * block, which may overlap bytes compared before. Words that differ are
 * compared byte-reversed, which orders them by their first byte in memory;
 * bytes that were compared twice are equal, so they do not decide. No word
 * is read that is not wholly inside the n bytes. Nothing goes on the
 * stack. Fewer than 4 bytes are compared one by one.
 *
 * The result is 1 or -1 from words and the difference of the bytes (as
 * unsigned char) below 4 bytes: the sign is what the C standard defines.
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
	cmp	r2, #4
	blo	.Ltiny
	ldr	r3, [r0]
	ldr	ip, [r1]
	cmp	r3, ip
	bne	.Ldiffer		@ blocks that differ at once (keys, names) leave here
	cmp	r2, #8
	blo	.Llast			@ 4 .. 7 bytes: the last word finishes it

	@ on to l's next word boundary: 1 .. 4 bytes, all of them compared
	and	r3, r0, #3
	rsb	r3, r3, #4
	add	r0, r0, r3
	add	r1, r1, r3
	sub	r2, r2, r3		@ 4 or more left
	subs	r2, r2, #8
	blo	2f
1:	ldr	r3, [r0], #4
	ldr	ip, [r1], #4
	cmp	r3, ip
	bne	.Ldiffer
	ldr	r3, [r0], #4
	ldr	ip, [r1], #4
	cmp	r3, ip
	bne	.Ldiffer
	subs	r2, r2, #8
	bhs	1b
2:	adds	r2, r2, #8		@ 0 .. 7 left
	beq	.Lequal
	cmp	r2, #4
	bls	.Llast			@ 1 .. 4: the last word covers them
	ldr	r3, [r0]		@ 5 .. 7: a word here, then the last
	ldr	ip, [r1]
	cmp	r3, ip
	bne	.Ldiffer
.Llast:
	@ the last word of each block; r2 bytes (1 .. 7) are left, and at
	@ least 4 bytes lie before the end
	add	r0, r0, r2
	add	r1, r1, r2
	ldr	r3, [r0, #-4]
	ldr	ip, [r1, #-4]
	cmp	r3, ip
	bne	.Ldiffer
.Lequal:
	mov	r0, #0
	bx	lr

.Ldiffer:
	rev	r3, r3
	rev	ip, ip
	cmp	r3, ip
	movhi	r0, #1
	mvnlo	r0, #0
	bx	lr

.Ltiny:
	@ 0 .. 3 bytes
	cmp	r2, #1
	blo	.Lequal
	ldrb	r3, [r0]
	ldrb	ip, [r1]
	subs	r3, r3, ip
	bne	.Lresult
	cmp	r2, #1
	beq	.Lequal
	ldrb	r3, [r0, #1]
	ldrb	ip, [r1, #1]
	subs	r3, r3, ip
	bne	.Lresult
	cmp	r2, #3
	blo	.Lequal
	ldrb	r3, [r0, #2]
	ldrb	ip, [r1, #2]
	sub	r3, r3, ip
.Lresult:
	mov	r0, r3
	bx	lr
	.size	NAME, . - NAME
