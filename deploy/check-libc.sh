#!/bin/sh
# SPDX-License-Identifier: MIT
# check-libc.sh NEW.apk OLD.apk: off-device checks of a musl package that carries memset.S and memcmp.S.
# Run in the n72-alpine container (cross tools and qemu-arm), from the n72-string directory:
#   docker run --rm -v ~/n72-linux:/work n72-alpine sh -c 'cd /work/n72-string && sh deploy/check-libc.sh NEW OLD'
# Leaves the two libraries in build/libc-new and build/libc-old.
set -e
NEW=${1:?usage: check-libc.sh NEW.apk OLD.apk}; OLD=${2:?}
T=armv6-alpine-linux-musleabihf-
Q="qemu-arm -cpu arm1176"
rm -rf build/libc-new build/libc-old; mkdir -p build/libc-new build/libc-old
tar -xzf "$NEW" -C build/libc-new 2>/dev/null
tar -xzf "$OLD" -C build/libc-old 2>/dev/null
N=build/libc-new/lib/ld-musl-armhf.so.1; O=build/libc-old/lib/ld-musl-armhf.so.1
ls -l $N $O
md5sum $N $O
fail=0

echo "== the routines in the new library are the assembly ones"
for f in memset memcmp; do
	${T}objdump -d --disassemble-symbols=$f $N | grep -E '^ +[0-9a-f]+:' > build/libc-new/$f.dis
	${T}objdump -d --disassemble-symbols=$f $O | grep -E '^ +[0-9a-f]+:' > build/libc-old/$f.dis
	echo "$f: new $(wc -l < build/libc-new/$f.dis) instructions, old $(wc -l < build/libc-old/$f.dis)"
done
grep -q '{r1, r3, r4, r5, r6, r7, r8, lr}' build/libc-new/memset.dis || { echo "FAIL: memset has no 32-byte store"; fail=1; }
grep -q 'rev' build/libc-new/memcmp.dis || { echo "FAIL: memcmp has no rev"; fail=1; }
grep -q '{r1, r3, r4, r5, r6, r7, r8, lr}' build/libc-old/memset.dis && { echo "FAIL: the old library has it too: wrong file?"; fail=1; }

echo "== the same symbols, and nothing else moved in the interface"
${T}nm -D --defined-only $N | awk '{print $2, $3}' | sort > build/libc-new/syms
${T}nm -D --defined-only $O | awk '{print $2, $3}' | sort > build/libc-old/syms
if diff build/libc-old/syms build/libc-new/syms > build/libc-new/syms.diff; then
	echo "$(wc -l < build/libc-new/syms) dynamic symbols, identical names and types"
else
	echo "FAIL: dynamic symbols differ"; cat build/libc-new/syms.diff; fail=1
fi
${T}readelf -lW $N | grep -E 'GNU_STACK|LOAD' > build/libc-new/phdr
${T}readelf -lW $O | grep -E 'GNU_STACK|LOAD' > build/libc-old/phdr
grep GNU_STACK build/libc-new/phdr
grep -q 'GNU_STACK.* RW  *0x' build/libc-new/phdr || { echo "FAIL: the stack would be executable"; fail=1; }
${T}readelf -dW $N | grep -E 'SONAME|TEXTREL|NEEDED' || true
${T}readelf -dW $N | grep -q TEXTREL && { echo "FAIL: text relocations"; fail=1; }

echo "== the exhaustive test, calling the library's memset and memcmp through the new loader"
${T}gcc -O2 -mcpu=arm1176jzf-s -mfpu=vfpv2 -mfloat-abi=hard -std=gnu11 -fno-builtin -Dn72_memset=memset -Dn72_memcmp=memcmp \
	-o build/test_libc test.c
${T}readelf -lW build/test_libc | grep -i 'interpreter'
$Q $N build/test_libc | tail -3 || { echo "FAIL: test with the new library"; fail=1; }
echo "(the same binary with the old library:)"
$Q $O build/test_libc | tail -1 || { echo "FAIL: test with the old library"; fail=1; }

echo "== programs of an Alpine armhf root through both loaders, same output"
R=/tmp/cr
if [ ! -x $R/bin/busybox ]; then
	mkdir -p $R/etc/apk/keys
	cp /usr/share/apk/keys/armhf/*.pub $R/etc/apk/keys/
	printf '%s\n' https://dl-cdn.alpinelinux.org/alpine/v3.24/main > $R/etc/apk/repositories
	apk add -q -U --root $R --arch armhf --initdb --keys-dir $R/etc/apk/keys --no-scripts busybox apk-tools dropbear >/dev/null 2>&1 || \
		echo "(could not make an armhf root: this part is skipped)"
fi
if [ -x $R/bin/busybox ]; then
	head -c 300000 /dev/urandom > /tmp/blob
	seq 1 20000 > /tmp/seq
	# every applet is named on busybox's own command line, so that it runs in the process the
	# loader started (a command inside "sh -c" would be exec'ed anew, with the system's library);
	# pipes are made here, each side its own run. $B is expanded when a case is evaluated.
	n=0
	for c in \
		'$B echo hello' \
		'$B md5sum /tmp/blob /tmp/seq' \
		'$B sha256sum /tmp/blob' \
		'$B sort -r /tmp/seq | $B md5sum' \
		'$B gzip -c /tmp/blob | $B gunzip -c | $B md5sum' \
		'$B gzip -c /tmp/seq | $B md5sum' \
		'$B grep -c 7 /tmp/seq' \
		'$B sed -n "s/9/x/gp" /tmp/seq | $B md5sum' \
		'$B awk "{ s += \$1 } END { print s }" /tmp/seq' \
		'$B tar -cf - -C /tmp seq blob | $B tar -tvf - | $B wc -l' \
		'$B cmp /tmp/blob /tmp/blob && echo same' \
		'$B cmp /tmp/blob /tmp/seq; echo rc $?' \
		'$B diff /tmp/seq /tmp/seq && echo nodiff' \
		'printf "%s\n" b a c | $B sort | $B tr "\n" " "' \
		'$B dd if=/dev/zero bs=65536 count=4 2>/dev/null | $B md5sum' \
		'$B od -An -tx1 -N 64 /tmp/blob | $B md5sum' \
		'$B expr 12345 \* 6789' \
		'$B wc /tmp/seq' \
		'$B sh -c "i=0; while [ \$i -lt 2000 ]; do i=\$((i + 1)); done; echo \$i; case abc in a*) echo glob;; esac"' \
		'$B find /tmp/cr/etc -type f | $B sort | $B md5sum' \
		'$B ls -l /tmp/cr/bin | $B wc -l'; do
		B="$Q $O --library-path $R/lib:$R/usr/lib $R/bin/busybox"; a=$(eval "$c" 2>&1)
		B="$Q $N --library-path $R/lib:$R/usr/lib $R/bin/busybox"; b=$(eval "$c" 2>&1)
		n=$((n + 1))
		if [ "$a" != "$b" ] || [ -z "$a" ]; then echo "FAIL: [$c] old: $a / new: $b"; fail=1; fi
		[ -n "$V" ] && echo "[$c] $b"
	done
	echo "$n busybox command lines, old and new library"
	for p in "$R/sbin/apk --version" "$R/usr/sbin/dropbear -V" "$R/usr/bin/dropbearkey -t ed25519 -f /tmp/k.$$"; do
		set -- $p
		a=$($Q $O --library-path $R/lib:$R/usr/lib "$@" 2>&1 | head -3 | grep -v 'Fingerprint\|^ssh-\|key' ; rm -f /tmp/k.$$)
		b=$($Q $N --library-path $R/lib:$R/usr/lib "$@" 2>&1 | head -3 | grep -v 'Fingerprint\|^ssh-\|key' ; rm -f /tmp/k.$$)
		if [ "$a" != "$b" ]; then echo "FAIL: [$p] old: $a / new: $b"; fail=1; else echo "$1: $b"; fi
	done
fi
[ $fail = 0 ] && echo "ALL PASS" || echo "FAILED"
exit $fail
