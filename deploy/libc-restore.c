/* SPDX-License-Identifier: MIT */
/*
 * libc-restore: put a saved C library back, for the day a new one does
 * not work. Linked statically, so it runs whatever /lib holds.
 *
 *	libc-restore now SRC DST
 *		copy SRC to DST's directory and rename it over DST
 *	libc-restore guard SECONDS OKFILE SRC DST
 *		go to the background; if OKFILE does not exist SECONDS from
 *		now, do the same. Start it before the new library goes in
 *		and create OKFILE once the checks have passed: a link that
 *		drops in between then costs SECONDS, not a restore over USB.
 *
 * What it did goes to LOG below (appended).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define LOG "/root/musl-old/restore.log"

static void say(const char *fmt, ...)
{
	char line[512];
	va_list ap;
	int n, fd;
	time_t now = time(NULL);

	n = snprintf(line, sizeof(line), "%ld pid %d: ", (long)now, (int)getpid());
	va_start(ap, fmt);
	n += vsnprintf(line + n, sizeof(line) - (size_t)n - 2, fmt, ap);
	va_end(ap);
	line[n++] = '\n';
	fd = open(LOG, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd >= 0) {
		if (write(fd, line, (size_t)n) < 0)
			;
		fsync(fd);
		close(fd);
	}
	if (write(2, line, (size_t)n) < 0)
		;
}

static int restore(const char *src, const char *dst)
{
	char tmp[512], dir[512], buf[65536], *slash;
	int in, out, dfd;
	ssize_t got;
	long total = 0;

	if (snprintf(tmp, sizeof(tmp), "%s.restore", dst) >= (int)sizeof(tmp)) {
		say("the name %s is too long", dst);
		return 1;
	}
	in = open(src, O_RDONLY);
	if (in < 0) {
		say("open %s: %s", src, strerror(errno));
		return 1;
	}
	out = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0755);
	if (out < 0) {
		say("create %s: %s", tmp, strerror(errno));
		return 1;
	}
	while ((got = read(in, buf, sizeof(buf))) > 0) {
		ssize_t done = 0;

		while (done < got) {
			ssize_t w = write(out, buf + done, (size_t)(got - done));

			if (w < 0) {
				say("write %s: %s", tmp, strerror(errno));
				unlink(tmp);
				return 1;
			}
			done += w;
		}
		total += got;
	}
	if (got < 0 || total == 0) {
		say("read %s: %s (%ld bytes)", src, got < 0 ? strerror(errno) : "empty", total);
		unlink(tmp);
		return 1;
	}
	if (fchmod(out, 0755) || fsync(out) || close(out)) {
		say("finish %s: %s", tmp, strerror(errno));
		unlink(tmp);
		return 1;
	}
	close(in);
	if (rename(tmp, dst)) {
		say("rename %s to %s: %s", tmp, dst, strerror(errno));
		unlink(tmp);
		return 1;
	}
	snprintf(dir, sizeof(dir), "%s", dst);
	slash = strrchr(dir, '/');
	if (slash) {
		slash[slash == dir ? 1 : 0] = 0;
		dfd = open(dir, O_RDONLY | O_DIRECTORY);
		if (dfd >= 0) {
			fsync(dfd);
			close(dfd);
		}
	}
	say("restored %s from %s, %ld bytes", dst, src, total);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc == 4 && !strcmp(argv[1], "now"))
		return restore(argv[2], argv[3]);
	if (argc == 6 && !strcmp(argv[1], "guard")) {
		long secs = strtol(argv[2], NULL, 10), i;
		const char *ok = argv[3];
		pid_t pid;

		if (secs < 5 || secs > 3600) {
			fprintf(stderr, "guard: 5 to 3600 seconds\n");
			return 2;
		}
		if (access(argv[4], R_OK)) {
			fprintf(stderr, "guard: %s: %s\n", argv[4], strerror(errno));
			return 2;
		}
		if (!access(ok, F_OK)) {
			fprintf(stderr, "guard: %s exists already; remove it first\n", ok);
			return 2;
		}
		pid = fork();
		if (pid < 0) {
			perror("fork");
			return 2;
		}
		if (pid > 0) {
			printf("guard pid %d: %s goes back over %s in %ld s unless %s appears\n", (int)pid, argv[4], argv[5],
			       secs, ok);
			return 0;
		}
		setsid();
		close(0);
		close(1);
		close(2);
		open("/dev/null", O_RDWR);
		if (dup(0) < 0 || dup(0) < 0)
			;
		say("guard started: %ld s, ok file %s", secs, ok);
		for (i = 0; i < secs; i++) {
			if (!access(ok, F_OK)) {
				say("guard: %s is there after %ld s, nothing restored", ok, i);
				return 0;
			}
			sleep(1);
		}
		if (!access(ok, F_OK)) {
			say("guard: %s is there, nothing restored", ok);
			return 0;
		}
		say("guard: no %s after %ld s, restoring", ok, secs);
		return restore(argv[4], argv[5]);
	}
	fprintf(stderr, "usage: libc-restore now SRC DST\n       libc-restore guard SECONDS OKFILE SRC DST\n");
	return 2;
}
