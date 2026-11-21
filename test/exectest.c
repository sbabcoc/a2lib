/*
** exec() under DOS 3.3 (DESIGN.md 5.10).
**
** Reads a line first, as a program that execs would, so DOS's video
** intercept is in its input state (3) when exec()'s stub sends its
** command. Then checks that each failure returns -1 with this program
** still running:
**
**   - a missing file (ENOENT)
**   - a T file (ENOEXEC)
**   - a bad name (EINVAL)
**   - a name with a comma, which a DOS command can't carry (EINVAL)
**   - an A file with a cmdline (EINVAL)
**
** and execs:
**
**   exectest, exectestvt  /6/2/ARGTEST with "PRE=<passed>/<total>" and four
**                         more arguments, one quoted, the last 100
**                         characters long, so the argument tail runs most
**                         of the way through page 2. argtest checks them
**                         and prints the summary.
**   execatest (-DEXECA)   EXECA, an Applesoft program this test writes,
**                         which prints EXECA OK.
**
** exectestvt is built with a2lib-vt.lib and run with the VideoTerm.
** Run under DOS 3.3 with the test disk in drive 2. Prints no summary of
** its own: if exec() returns, the run times out.
*/

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <apple2.h>
#include "dos33_filetype.h"

#define TOTAL   5

static unsigned char passed;
static char line[40];
#ifndef EXECA
static char cmdline[128];
#endif

/* 10 PRINT "EXECA OK", tokenized for $801: link, line number, PRINT, the
** string, end of line; then the end of the program */
static const unsigned char execa[] = {
    0x11, 0x08, 10, 0, 0xBA, '"', 'E', 'X', 'E', 'C', 'A', ' ', 'O', 'K',
    '"', 0, 0, 0
};

static void check (const char* what, int ok)
{
    if (ok) {
        ++passed;
    } else {
        printf ("FAIL %s (ERRNO %d)\n", what, errno);
    }
}

static int fails_with (const char* name, const char* args, int err)
{
    errno = 0;
    return exec (name, args) == -1 && errno == err;
}

static void make_file (const char* name, unsigned char type,
                       const void* data, unsigned len)
{
    int fd;

    _filetype = type;
    fd = open (name, O_WRONLY | O_CREAT | O_TRUNC);
    if (fd >= 0) {
        write (fd, data, len);
        close (fd);
    }
}

int main (void)
{
    printf ("A2LIB EXEC TEST (DOS 3.3)\n");
    printf ("TYPE A WORD, PRESS RETURN:\n");
    fgets (line, sizeof (line), stdin);

    make_file ("2/EXECT", DOS33_T_TXT, "TEXT\r", 5);
    make_file ("2/EXECA", DOS33_T_BAS, execa, sizeof (execa));
    make_file ("2/EXEC,B", DOS33_T_BIN, "X", 1);

    check ("MISSING FILE", fails_with ("2/NOSUCH", NULL, ENOENT));
    check ("T FILE", fails_with ("/6/2/EXECT", NULL, ENOEXEC));
    check ("BAD NAME", fails_with ("1BAD", NULL, EINVAL));
    check ("A FILE WITH CMDLINE", fails_with ("2/EXECA", "X", EINVAL));
    check ("COMMA IN THE NAME", fails_with ("EXEC,B", NULL, EINVAL));
    printf ("PRE-EXEC %u/%u\n", passed, TOTAL);

#ifdef EXECA
    exec ("/6/2/EXECA", NULL);
#else
    sprintf (cmdline, "PRE=%u/%u ONE \"TWO 2\" THREE ", passed, TOTAL);
    memset (cmdline + strlen (cmdline), 'X', 100);
    exec ("/6/2/ARGTEST", cmdline);
#endif
    printf ("EXEC RETURNED (ERRNO %d)\n", errno);
    return 0;
}
