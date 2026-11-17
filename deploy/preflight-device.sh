#!/bin/sh
# SPDX-License-Identifier: MIT
# preflight-device.sh: on the iPod, run programs with the new C library as their loader and
# compare with the installed one. Nothing in /lib changes. Expects in /root/musl-test:
# ld-musl-armhf.so.1 (the new library) and test_libc (test.c built against the libc names).
# Writes preflight.log and, at the end, preflight.done ("PASS" or "FAIL").
cd /root/musl-test || exit 1
N=/root/musl-test/ld-musl-armhf.so.1; O=/lib/ld-musl-armhf.so.1
rm -f preflight.done
exec > preflight.log 2>&1
fail=0
cat /proc/loadavg
md5sum $N $O

head -c 300000 /dev/urandom > blob
seq 1 20000 > seq
D=/root/musl-test
echo "== busybox applets, each in the process the loader started"
n=0
for c in \
	'$B echo hello' \
	'$B md5sum $D/blob $D/seq' \
	'$B sha256sum $D/blob' \
	'$B sort -r $D/seq | $B md5sum' \
	'$B gzip -c $D/blob | $B gunzip -c | $B md5sum' \
	'$B gzip -c $D/seq | $B md5sum' \
	'$B grep -c 7 $D/seq' \
	'$B sed -n "s/9/x/gp" $D/seq | $B md5sum' \
	'$B awk "{ s += \$1 } END { print s }" $D/seq' \
	'$B tar -cf - -C $D seq blob | $B tar -tvf - | $B wc -l' \
	'$B cmp $D/blob $D/blob && echo same' \
	'$B cmp $D/blob $D/seq; echo rc $?' \
	'$B diff $D/seq $D/seq && echo nodiff' \
	'printf "%s\n" b a c | $B sort | $B tr "\n" " "' \
	'$B dd if=/dev/zero bs=65536 count=4 2>/dev/null | $B md5sum' \
	'$B od -An -tx1 -N 64 $D/blob | $B md5sum' \
	'$B expr 12345 \* 6789' \
	'$B wc $D/seq' \
	'$B sh -c "i=0; while [ \$i -lt 2000 ]; do i=\$((i + 1)); done; echo \$i; case abc in a*) echo glob;; esac"' \
	'$B find /etc/apk -type f | $B sort | $B md5sum' \
	'$B ls -l /bin | $B wc -l' \
	'$B ls /' \
	'$B cat /proc/version' \
	'$B df / | $B wc -l'; do
	B="$O /bin/busybox"; a=$(eval "$c" 2>&1)
	B="$N /bin/busybox"; b=$(eval "$c" 2>&1)
	n=$((n + 1))
	if [ "$a" != "$b" ] || [ -z "$a" ]; then echo "FAIL: [$c] old: $a / new: $b"; fail=1; fi
done
echo "$n command lines compared"

echo "== other programs: the same output with both"
PY='import hashlib, zlib, json, re; d = bytes(range(256)) * 4000; print(hashlib.sha256(d).hexdigest(), len(d), d.count(b"\x00"), zlib.crc32(d), sorted([3, 1, 2]), json.dumps({"a": [1, 2.5, "x"]}), re.findall(r"\d+", "a12b345"), d == bytes(bytearray(d)), bytes(1000) == bytearray(1000))'
both() { # label, command...
	label=$1; shift
	a=$($O "$@" 2>&1); ra=$?
	b=$($N "$@" 2>&1); rb=$?
	if [ "$a" != "$b" ] || [ $ra != $rb ] || [ -z "$b" ]; then
		echo "FAIL: $label: old ($ra): $(echo "$a" | head -3) / new ($rb): $(echo "$b" | head -3)"; fail=1
	else
		echo "$label: $(echo "$b" | head -1 | cut -c1-110) [$(echo "$b" | wc -l) lines, exit $rb]"
	fi
}
both "apk --version" /sbin/apk --version
both "apk info" /sbin/apk info
both "apk info -L musl" /sbin/apk info -L musl
both "dropbear -V" /usr/sbin/dropbear -V
both "wpa_supplicant -v" /sbin/wpa_supplicant -v
both "bluetoothd -v" /usr/lib/bluetooth/bluetoothd -v
both "bluealsa -V" /usr/bin/bluealsa --version
both "amixer scontrols" /usr/bin/amixer -c 0 scontrols
both "gst-inspect version" /usr/bin/gst-inspect-1.0 --version
both "python3" /usr/bin/python3 -c "$PY"
both "strace -V" /usr/bin/strace -V
both "iw list" /usr/sbin/iw list

echo "== the exhaustive test against the library's own memset and memcmp"
t=$($N ./test_libc 2>&1 | tail -3); echo "$t"
case "$t" in *"6686446 checks, 0 failures") ;; *) echo "FAIL: test_libc with the new library"; fail=1 ;; esac

echo "== RetroArch's core benchmark (no display, no sound): every frame's checksum must match"
R=/root/retro
RB=$R/retrobench; [ -x $D/retrobench ] && RB=$D/retrobench	# a build that knows RETROBENCH_CRC
if [ -x $RB ]; then
	export LD_LIBRARY_PATH=$R/lib RETROBENCH_CRC=1
	$O $RB $R/cores/snes9x2005_libretro.so $R/games/snes/gothicvania.sfc 600 100 > retro-old.out 2>&1; echo "old exit $?"
	$N $RB $R/cores/snes9x2005_libretro.so $R/games/snes/gothicvania.sfc 600 100 > retro-new.out 2>&1; echo "new exit $?"
	unset LD_LIBRARY_PATH RETROBENCH_CRC
	echo "old: $(tail -3 retro-old.out)"
	echo "new: $(tail -3 retro-new.out)"
	ca=$(grep 'frames checksum' retro-old.out); cb=$(grep 'frames checksum' retro-new.out)
	if [ -z "$ca" ] || [ "$ca" != "$cb" ]; then echo "FAIL: retrobench frame checksums: old [$ca] new [$cb]"; fail=1; fi
fi

if [ -x /root/n72hle-test/strbench.final ]; then
	echo "== the benchmark of the final routines (static)"
	/root/n72hle-test/strbench.final > strbench-final.out 2>&1; echo "bench exit $?"
fi
rm -f blob seq
cat /proc/loadavg
[ $fail = 0 ] && echo PASS || echo FAIL
[ $fail = 0 ] && echo PASS > preflight.done || echo FAIL > preflight.done
