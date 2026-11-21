/*
** Probe for exec() under DOS 3.3 (DESIGN.md 5.10): can a running cc65
** program send DOS commands through COUT, and does BLOAD leave page 2 past
** the command line alone?
**
** exec() puts its arguments in page 2 after the BRUN command, which DOS
** stores at $200, and relies on BRUN's BLOAD ($A38E calls it) not to
** touch them. This probe sends BSAVE and BLOAD through the monitor's COUT
** ($FDED, through DOS's video intercept), as exec()'s stub will, and
** checks:
**
**   - the file BLOADs back as it was BSAVEd (commands work from here)
**   - DOS stored the BLOAD command at $200: $84, the command, $8D
**   - $230-$2FF, where exec()'s argument tail goes, is unchanged
**
** Built with a2lib-dos33.lib. Run under DOS 3.3 with a writable disk in
** drive 2 (make emutest's test disk). Ends with its summary.
*/

#include <stdio.h>
#include <string.h>

void __fastcall__ mon_cout (char c);    /* cswcout.s: sets the high bit */

#define PAGE2       ((unsigned char*) 0x0200)
#define TAIL_START  0x30                /* exec()'s tail: $230 on */
#define TAIL_END    0x100
#define LEN         256

static unsigned char src[LEN], dst[LEN];
static char cmd[40];
static unsigned char passed, total;

static void check (const char* what, int ok)
{
    ++total;
    if (ok) {
        ++passed;
    }
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
}

/* Send a DOS command: CR (to state 0), Ctrl-D, the command, CR. */
static void dos_cmd (const char* s)
{
    mon_cout (0x0D);
    mon_cout (0x04);
    while (*s) {
        mon_cout (*s++);
    }
    mon_cout (0x0D);
}

static unsigned char sentinel (unsigned i)
{
    return (unsigned char) (i * 7 + 0x35);
}

int main (void)
{
    unsigned i;
    unsigned char ok;

    printf ("A2LIB BLOAD PROBE (DOS 3.3)\n");

    for (i = 0; i < LEN; ++i) {
        src[i] = (unsigned char) (i ^ 0x5A);
    }
    sprintf (cmd, "BSAVE PROBEBIN,A%u,L%u,D2", (unsigned) src, LEN);
    dos_cmd (cmd);

    /* The tail region, filled after BSAVE: only BLOAD is checked */
    for (i = TAIL_START; i < TAIL_END; ++i) {
        PAGE2[i] = sentinel (i);
    }
    sprintf (cmd, "BLOAD PROBEBIN,A%u,D2", (unsigned) dst);
    dos_cmd (cmd);

    check ("BSAVE, BLOAD ROUND TRIP", memcmp (src, dst, LEN) == 0);

    /* $200: Ctrl-D, the command, CR, all with the high bit set */
    ok = PAGE2[0] == 0x84;
    for (i = 0; ok && cmd[i]; ++i) {
        ok = PAGE2[1 + i] == (unsigned char) (cmd[i] | 0x80);
    }
    check ("COMMAND STORED AT $200", ok && PAGE2[1 + i] == 0x8D);

    ok = 1;
    for (i = TAIL_START; ok && i < TAIL_END; ++i) {
        ok = PAGE2[i] == sentinel (i);
    }
    if (!ok) {
        printf ("  FIRST CHANGE AT $%03X\n", 0x200 + i - 1);
    }
    check ("BLOAD KEEPS $230-$2FF", ok);

    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    return 0;
}
