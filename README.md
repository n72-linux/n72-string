n72-string
==========

memset and memcmp for the ARM1176JZF-S (iPod touch 2G, Linux/Alpine/musl).
musl has an assembly memcpy for ARM but takes memset and memcmp from C: its
memset stores a word at a time, its memcmp is a byte loop.

- memset.S: from 64 bytes, up to the cache line and then 32 bytes per store
  (one STM, one line); below that 8 bytes per store; 4 to 15 bytes by word
  stores that overlap.
- memcmp.S: only words from 4 bytes up: the first word of each block, words
  from the first block's next boundary, the last word (overlapping). The
  first differing words are compared byte-reversed. No stack use.

Why the cache line matters for memset: this CPU does not bring a line into
the cache on a store, so a fill of uncached memory goes to the bus as it is
written. Per byte of a long fill on the iPod, by where the 32-byte stores
start within a line: 1.2 ns on the line, 1.8 ns at 16 bytes into it, 2.0 at
8, 2.6 at 12, 3.0 at 4; musl's C memset 5.8 to 6.2.

Measured on the iPod against musl 1.2.6 (results/):

| | musl | here |
|---|---|---|
| memset, 64 KiB, uncached, any start | 360-380 us | 75-79 us |
| memset, 4096 bytes, cached | 4.2-4.6 us | 1.1 us |
| memset, 16 to 64 bytes, cached | 98-161 ns | 85-134 ns |
| memset, 1 to 3 bytes | 45-55 ns | 42-47 ns |
| memcmp, 4096 equal bytes | 62.3 us | 12.7-14.7 us |
| memcmp, 16 equal bytes | 297 ns | 110-136 ns |
| memcmp, 4 to 7 equal bytes | 116-161 ns | 64-72 ns |
| memcmp, 1 to 3 equal bytes | 70-100 ns | 55-76 ns |
| memcmp, first byte differs | 47 ns | 49-53 ns |

`make check` runs test.c under qemu-arm: memset over every start alignment
0..63 and length 0..600 plus large blocks with several fill values (bytes,
neighbours, return value); memcmp over every alignment 0..7 of both blocks
and length 0..600 plus large blocks, equal and differing at many places both
ways round (sign only). Blocks end at an unmapped page, so a load or store
past the end faults. The test was checked against 30 deliberately broken versions (a byte too
many, a wrong return value, words compared in the wrong byte order, a word
read too many, each alignment step and each compare taken out in turn):
each is caught. The same test passes on the iPod itself.

`build/bench` compares with the C library's on the machine it runs on; its
buffers lie on a cache line, and long fills are also timed by their start
within the line.

Meant to go into Alpine's musl package for the N72 as
src/string/arm/memset.S and memcmp.S (build with -DN72_STRING_LIBC for the
libc names): n72-alpine/aports/musl (musl-1.2.6-r50). Installed after
deploy/check-libc.sh (off-device) and deploy/preflight-device.sh (on the
single programs). deploy/libc-restore.c is the static tool that puts the old
library back if a new one does not work; its guard mode was running during
the install and was not needed.
