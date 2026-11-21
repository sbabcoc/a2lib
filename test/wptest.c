/*
** What the DOS 3.3 file layer does when its disk is write-protected while
** a file is open (DESIGN.md 5.11).
**
** A B file is written to, then the disk is protected before close():
** close() must fail with EACCES, and keep the file open, since DOS's
** CLOSE couldn't write what it holds. Made writable again, a second
** close() must succeed and save every byte.
**
** Run by make emutest on its own disk in drive 2: the script protects the
** disk at "PROTECT DISK 2" and makes it writable at "MAKE DISK 2
** WRITABLE" (ReplicApple2Plus's --protect and --writable). By hand, change
** the disk's protection at each prompt. Ends with its summary.
*/

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <conio.h>
#include "dos33_filetype.h"     /* DOS33_T_* (-I include) */

static unsigned char passed, total;
static char buf[16];

static void check (const char* what, int ok)
{
    ++total;
    if (ok) {
        ++passed;
    }
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
}

/* Ask for the disk to be changed, and wait until it has been */
static void prompt (const char* what)
{
    printf ("%s, PRESS A KEY\n", what);
    cgetc ();
}

int main (void)
{
    int fd;
    int n;
    int closed;

    /* After BRUN, the cursor can still be at the end of the command line */
    if (wherex () != 0) {
        putchar ('\n');
    }
    printf ("A2LIB WRITE-PROTECT TESTS\n");

    _filetype = DOS33_T_BIN;
    _auxtype = 0x2000;
    remove ("B.WP");            /* Left over from an earlier run */
    fd = open ("B.WP", O_WRONLY | O_CREAT | O_TRUNC);
    check ("MAKE B.WP", fd >= 0 && write (fd, "ABCD", 4) == 4 && close (fd) == 0);

    /* More bytes, held in DOS's buffers until CLOSE */
    fd = open ("B.WP", O_WRONLY | O_APPEND);
    check ("APPEND", fd >= 0 && write (fd, "EFGH", 4) == 4);

    prompt ("PROTECT DISK 2");
    errno = 0;
    closed = close (fd);
    check ("CLOSE PROTECTED: EACCES", closed == -1 && errno == EACCES);

    prompt ("MAKE DISK 2 WRITABLE");
    check ("CLOSE AGAIN", close (fd) == 0);

    fd = open ("B.WP", O_RDONLY);
    n = fd >= 0 ? read (fd, buf, sizeof (buf)) : -1;
    close (fd);
    check ("ALL 8 BYTES SAVED", n == 8 && memcmp (buf, "ABCDEFGH", 8) == 0);
    remove ("B.WP");

    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    return 0;
}
