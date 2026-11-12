/*
** DOS 3.3 file layer tests (DESIGN.md section 5).
**
** Run from a DOS 3.3 disk with a writable disk in the default drive.
** Output fits a 40x24 screen: one line per group with its pass count,
** failed checks indented beneath it (at most MAX_SHOWN in total), and a
** summary. Lines stay under 40 characters, since a full 40-character line
** makes the Apple II wrap and insert a blank line. The screen text is
** meant to be compared by an emulator test fixture (DESIGN.md section 8).
*/

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <apple2.h>
#include <conio.h>
#include <sys/stat.h>
#include <dirent.h>             /* a2lib's DOS 3.3 dirent.h (-I include) */

/* Failure lines shown: 24 rows less the BRUN line, the title, 10 groups,
** the overflow line, the summary and the prompt after exit. */
#define MAX_SHOWN   9
#define MAX_GROUP   10          /* Most checks in one group */

static unsigned char passed, total;         /* All groups */
static unsigned char gpassed, gtotal;       /* Current group */
static const char* gfailed[MAX_GROUP];      /* Current group's failures */
static unsigned char ngfailed;
static unsigned char shown, hidden;         /* Failure lines */

static void check (const char* what, int ok)
{
    ++gtotal;
    if (ok) {
        ++gpassed;
    } else if (ngfailed < MAX_GROUP) {
        gfailed[ngfailed++] = what;
    }
}

/* Print the group's line and its failures, then start a new group */
static void group (const char* name)
{
    unsigned char i;

    printf ("%-32s%2u/%u\n", name, gpassed, gtotal);
    for (i = 0; i < ngfailed; ++i) {
        if (shown < MAX_SHOWN) {
            printf ("  FAIL %s\n", gfailed[i]);
            ++shown;
        } else {
            ++hidden;
        }
    }
    passed += gpassed;
    total += gtotal;
    gpassed = gtotal = ngfailed = 0;
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

/* Write a file of the current _filetype with the given contents */
static void make_file (const char* name, const void* data, unsigned len)
{
    int fd = open (name, O_WRONLY | O_CREAT | O_TRUNC);

    write (fd, data, len);
    close (fd);
}

/* Read one byte at the current position; -1 at the end */
static int byte_at (int fd)
{
    unsigned char c;

    return read (fd, &c, 1) == 1 ? c : -1;
}

/* lseek (DESIGN.md 5.7) */
static void seek_tests (void)
{
    static const unsigned char bdata[] = { 1, 2, 3, 4, 5 };
    int fd;

    /* T files: each whence; any position; 16-bit limit */
    _filetype = PRODOS_T_TXT;
    make_file ("T.SEEK", "ABCDEFG", 7);
    fd = open ("T.SEEK", O_RDWR);
    check ("T seek end", lseek (fd, 0, SEEK_END) == 7);
    check ("T seek set", lseek (fd, 2, SEEK_SET) == 2 && byte_at (fd) == 'C');
    check ("T seek cur", lseek (fd, -1, SEEK_CUR) == 2 && byte_at (fd) == 'C');
    check ("T seek past end", lseek (fd, 10, SEEK_SET) == 10);
    errno = 0;
    check ("negative position", lseek (fd, -1, SEEK_SET) == -1 && errno == EINVAL);
    errno = 0;
    check ("16-bit limit", lseek (fd, 0x10000L, SEEK_SET) == -1 && errno == EINVAL);
    lseek (fd, 1, SEEK_SET);
    write (fd, "X", 1);
    lseek (fd, 0, SEEK_SET);
    check ("T overwrite", read (fd, buf, sizeof (buf)) == 7
                          && memcmp (buf, "AXCDEFG", 7) == 0);
    close (fd);

    /* T files: records of a random-access file (DESIGN.md 5.2) */
    fd = open ("T.RECORDS", O_RDWR | O_CREAT | O_TRUNC);
    write (fd, "R0", 2);
    lseek (fd, 10, SEEK_SET);
    write (fd, "R1", 2);
    lseek (fd, 10, SEEK_SET);
    check ("T record read", read (fd, buf, sizeof (buf)) == 2
                            && memcmp (buf, "R1", 2) == 0);
    close (fd);

    /* B files: not past the recorded length */
    _filetype = PRODOS_T_BIN;
    make_file ("B.SEEK", bdata, sizeof (bdata));
    fd = open ("B.SEEK", O_RDONLY);
    check ("B seek", lseek (fd, 3, SEEK_SET) == 3 && byte_at (fd) == 4);
    errno = 0;
    check ("B past end", lseek (fd, 6, SEEK_SET) == -1 && errno == ESPIPE);
    close (fd);
}

/* remove and rename (DESIGN.md 5.5) */
static void remove_rename (void)
{
    int fd;

    _filetype = PRODOS_T_TXT;
    make_file ("T.GONE", "X", 1);
    check ("remove", remove ("T.GONE") == 0
                     && open ("T.GONE", O_RDONLY) == -1 && errno == ENOENT);
    errno = 0;
    check ("remove missing", remove ("T.GONE") == -1 && errno == ENOENT);

    remove ("T.NEW");           /* Left over from an earlier run */
    make_file ("T.OLD", "X", 1);
    check ("rename", rename ("T.OLD", "T.NEW") == 0);
    fd = open ("T.NEW", O_RDONLY);
    check ("renamed file", fd >= 0 && open ("T.OLD", O_RDONLY) == -1);
    close (fd);
    errno = 0;
    check ("rename onto existing", rename ("T.TEST", "T.NEW") == -1 && errno == EEXIST);
    errno = 0;
    check ("rename new suffix", rename ("T.NEW", "T.X,D1") == -1 && errno == EINVAL);
    errno = 0;
    check ("rename missing", rename ("T.OLD", "T.Y") == -1 && errno == ENOENT);
}

/* stat (DESIGN.md 5.8) */
static void stat_tests (void)
{
    static struct stat st;

    check ("stat T", stat ("T.TEST", &st) == 0);
    check ("stat T fields", st.st_mode == S_IFREG && st.st_type == PRODOS_T_TXT
                            && st.st_access == 0xC3);
    check ("stat T size", st.st_size == 7);
    check ("stat B", stat ("B.TEST", &st) == 0 && st.st_type == PRODOS_T_BIN);
    check ("stat B load address", st.st_auxtype == 0x2000);
    check ("stat B size", st.st_size == 6);
    errno = 0;
    check ("stat missing", stat ("NO.SUCH.FILE", &st) == -1 && errno == ENOENT);
}

/* Directories (DESIGN.md 5.9) */
static void dir_tests (void)
{
    static struct stat st;
    static char first[31];
    DIR* d;
    struct dirent* e;
    unsigned char entries = 0, found_t = 0, found_b = 0, gone = 0;
    unsigned t_blocks = 0;

    d = opendir ("");
    check ("opendir", d != NULL);
    if (d == NULL) {
        return;
    }
    while ((e = readdir (d)) != NULL) {
        if (entries++ == 0) {
            strcpy (first, e->d_name);
        }
        if (strcmp (e->d_name, "T.TEST") == 0) {
            found_t = e->d_type == PRODOS_T_TXT && e->d_dostype == 0x00
                      && e->d_access == 0xC3 && e->d_sectors > 0
                      && e->d_blocks == (e->d_sectors + 1) / 2;
            t_blocks = e->d_blocks;
        } else if (strcmp (e->d_name, "B.TEST") == 0) {
            found_b = e->d_type == PRODOS_T_BIN && e->d_dostype == 0x04;
        } else if (strcmp (e->d_name, "T.GONE") == 0) {
            gone = 1;
        }
    }
    check ("readdir T entry", found_t);
    check ("readdir B entry", found_b);
    check ("removed file not listed", !gone);
    rewinddir (d);
    e = readdir (d);
    check ("rewinddir", e != NULL && strcmp (e->d_name, first) == 0);
    check ("closedir", closedir (d) == 0);

    d = opendir (",V0");
    check ("opendir suffix", d != NULL);
    if (d) {
        closedir (d);
    }
    errno = 0;
    check ("opendir bad location", opendir ("X") == NULL && errno == EINVAL);
    check ("stat blocks = d_blocks", stat ("T.TEST", &st) == 0
                                     && t_blocks > 0 && st.st_blocks == t_blocks);
}

/* stdio on top of the POSIX layer */
static void stdio_layer (void)
{
    FILE* f;

    _filetype = PRODOS_T_TXT;
    f = fopen ("T.STDIO", "w");
    check ("fopen w", f != NULL);
    if (f) {
        fprintf (f, "LINE %d\n", 42);
        fclose (f);
    }

    f = fopen ("T.STDIO", "r");
    check ("fopen r", f != NULL);
    check ("fgets", f != NULL
                    && fgets ((char*) buf, sizeof (buf), f) != NULL
                    && strcmp ((char*) buf, "LINE 42\n") == 0);
    if (f) {
        fclose (f);
    }
}

int main (void)
{
    /* After a DOS command such as BRUN, the cursor can still be at the end
    ** of the command line; start on a new line so the title doesn't wrap. */
    if (wherex () != 0) {
        putchar ('\n');
    }
    printf ("A2LIB DOS 3.3 FILE TESTS\n");
    text_roundtrip ();          group ("T FILE ROUND TRIP");
    text_reject ();             group ("T FILE 8-BIT REJECTION");
    text_append_truncate ();    group ("T FILE APPEND, TRUNCATE");
    binary_header ();           group ("B FILE HEADER");
    open_flags_names ();        group ("OPEN FLAGS, NAMES");
    stdio_layer ();             group ("STDIO");
    seek_tests ();              group ("LSEEK");
    remove_rename ();           group ("REMOVE, RENAME");
    stat_tests ();              group ("STAT");
    dir_tests ();               group ("DIRECTORY");
    if (hidden) {
        printf ("  (%u MORE FAILURES)\n", hidden);
    }
    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    return 0;
}
