n72-string
==========

memset and memcmp for the ARM1176JZF-S (iPod touch 2G, Linux/Alpine/musl).
musl has an assembly memcpy for ARM but takes memset and memcmp from C: its
memset stores a word at a time, its memcmp is a byte loop.

- memset.S: 32 bytes per store (one STM), then 8, then the tail.
- memcmp.S: a word of each block per step once the first is aligned; the
  first differing words are compared byte-reversed.

`make check` runs test.c under qemu-arm: memset over every start alignment
0..63 and length 0..600 plus large blocks with several fill values (bytes,
neighbours, return value); memcmp over every alignment 0..7 of both blocks
and length 0..600 plus large blocks, equal and differing at many places both
ways round (sign only). Blocks end at an unmapped page, so a load or store
past the end faults. The test was checked against four deliberately broken
versions (a byte too many, a wrong return value, words compared in the wrong
byte order, a word read too many): each is caught.

`build/bench` compares with the C library's on the machine it runs on.

Meant to go into Alpine's musl package for the N72 as
src/string/arm/memset.S and memcmp.S (build with -DN72_STRING_LIBC for the
libc names). Not installed anywhere yet.
