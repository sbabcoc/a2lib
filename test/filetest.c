/*
** DOS 3.3 file layer tests (DESIGN.md section 5).
**
** Run from a DOS 3.3 disk with a writable disk in the default drive.
** Prints one line per check and a summary; the screen text is meant to be
** compared by an emulator test fixture (DESIGN.md section 8).
*/

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <apple2.h>

static unsigned char failures;

static void check (const char* what, int ok)
{
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) {
        ++failures;
    }
}

static unsigned char buf[64];

/* T files: every byte $00-$7F round-trips, including $00, \n and \r */
static void text_roundtrip (void)
{
    static const unsigned char data[] = { 'A', '\n', 'B', '\r', 0, 'C', 0x7F };
    int fd;
    int n;

    _filetype = PRODOS_T_TXT;
    fd = open ("T.TEST", O_WRONLY | O_CREAT | O_TRUNC);
    check ("T create", fd >= 0);
    n = write (fd, data, sizeof (data));
    check ("T write", n == sizeof (data));
    check ("T close", close (fd) == 0);

    fd = open ("T.TEST", O_RDONLY);
    check ("T reopen", fd >= 0);
    n = read (fd, buf, sizeof (buf));
    check ("T read length", n == sizeof (data));
    check ("T read bytes", n == sizeof (data) && memcmp (buf, data, n) == 0);
    check ("T read at end", read (fd, buf, sizeof (buf)) == 0);
    close (fd);
}

/* T files: 8-bit data is rejected, and nothing is written */
static void text_reject (void)
{
    static const unsigned char bad[] = { 'O', 'K', 0x80 };
    int fd;

    _filetype = PRODOS_T_TXT;
    fd = open ("T.REJECT", O_WRONLY | O_CREAT | O_TRUNC);
    errno = 0;
    check ("T reject 8-bit", write (fd, bad, sizeof (bad)) == -1 && errno == EINVAL);
    close (fd);

    fd = open ("T.REJECT", O_RDONLY);
    check ("T reject wrote nothing", read (fd, buf, sizeof (buf)) == 0);
    close (fd);
}

/* T files: O_APPEND writes at the end; O_TRUNC empties */
static void text_append_truncate (void)
{
    int fd;
    int n;

    _filetype = PRODOS_T_TXT;
    fd = open ("T.APPEND", O_WRONLY | O_CREAT | O_TRUNC);
    write (fd, "ONE", 3);
    close (fd);
    fd = open ("T.APPEND", O_WRONLY | O_APPEND);
    write (fd, "TWO", 3);
    close (fd);

    fd = open ("T.APPEND", O_RDONLY);
    n = read (fd, buf, sizeof (buf));
    check ("T append", n == 6 && memcmp (buf, "ONETWO", 6) == 0);
    close (fd);

    fd = open ("T.APPEND", O_WRONLY | O_TRUNC);
    write (fd, "X", 1);
    close (fd);
    fd = open ("T.APPEND", O_RDONLY);
    n = read (fd, buf, sizeof (buf));
    check ("T truncate", n == 1 && buf[0] == 'X');
    close (fd);
}

/* B files: header hidden; load address from _auxtype; exact length */
static void binary_header (void)
{
    static const unsigned char data[] = { 0x00, 0x80, 0xFF, 0x0A, 0x0D };
    int fd;
    int n;

    _filetype = PRODOS_T_BIN;
    _auxtype = 0x2000;
    fd = open ("B.TEST", O_WRONLY | O_CREAT | O_TRUNC);
    check ("B create", fd >= 0);
    check ("B write", write (fd, data, sizeof (data)) == sizeof (data));
    check ("B close", close (fd) == 0);

    fd = open ("B.TEST", O_RDONLY);
    n = read (fd, buf, sizeof (buf));
    check ("B exact length", n == sizeof (data));
    check ("B bytes unchanged", n == sizeof (data) && memcmp (buf, data, n) == 0);
    close (fd);

    /* Append extends the recorded length */
    fd = open ("B.TEST", O_WRONLY | O_APPEND);
    write (fd, "Z", 1);
    close (fd);
    fd = open ("B.TEST", O_RDONLY);
    n = read (fd, buf, sizeof (buf));
    check ("B append", n == sizeof (data) + 1 && buf[sizeof (data)] == 'Z');
    close (fd);
}

/* open() flags and names */
static void open_flags_names (void)
{
    int fd;

    errno = 0;
    check ("missing file", open ("NO.SUCH.FILE", O_RDONLY) == -1 && errno == ENOENT);

    errno = 0;
    fd = open ("T.TEST", O_WRONLY | O_CREAT | O_EXCL);
    check ("O_EXCL existing", fd == -1 && errno == EEXIST);

    errno = 0;
    check ("name must start with a letter", open ("1ABC", O_RDONLY) == -1 && errno == EINVAL);
    errno = 0;
    check ("bad slot", open ("T.TEST,S9", O_RDONLY) == -1 && errno == EINVAL);
    errno = 0;
    check ("bad suffix", open ("T.TEST,X1", O_RDONLY) == -1 && errno == EINVAL);

    fd = open ("t.test", O_RDONLY);
    check ("names are case-insensitive", fd >= 0);
    close (fd);
}

/* stdio on top of the POSIX layer */
static void stdio_layer (void)
{
    FILE* f;

    _filetype = PRODOS_T_TXT;
    f = fopen ("T.STDIO", "w");
    check ("fopen w", f != NULL);
    fprintf (f, "LINE %d\n", 42);
    fclose (f);

    f = fopen ("T.STDIO", "r");
    check ("fopen r", f != NULL);
    check ("fgets", fgets ((char*) buf, sizeof (buf), f) != NULL
                    && strcmp ((char*) buf, "LINE 42\n") == 0);
    fclose (f);
}

int main (void)
{
    text_roundtrip ();
    text_reject ();
    text_append_truncate ();
    binary_header ();
    open_flags_names ();
    stdio_layer ();
    printf ("%s: %u FAILED\n", failures ? "DONE" : "ALL PASSED", failures);
    return 0;
}
