/*
** Does output through the monitor's COUT still reach the display backend
** after stdio input under DOS 3.3? (DESIGN.md section 9, open item.)
**
** Built twice: cswtest with apple2-dos33-vt.lib (run with the VideoTerm
** in slot 3), and cswwtest with apple2-dos33-vtwin.lib (run without it,
** for the 40-column window). Run under DOS 3.3. Writes a character through
** COUT ($FDED, through CSW) before and after stdio input, reads it back
** from the backend with cpeekc, and shows where CSW and DOS's saved CSW
** ($AA53) point at each stage. The backend's output routine should be in
** one of the two, and the character should arrive both times
** (DESIGN.md 3.5).
*/

#include <stdio.h>
#include <conio.h>
#ifdef C40WIN
#include <c40win.h>
#endif

void __fastcall__ mon_cout (char c);
unsigned csw (void);
unsigned dos_csw (void);

static unsigned char failures;

static void check (const char* what, int ok)
{
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) {
        ++failures;
    }
}

static unsigned char row = 6;   /* Next row for results */

static char peek_at (unsigned char x, unsigned char y)
{
    char c;

    gotoxy (x, y);
    c = cpeekc ();
    gotoxy (0, row++);          /* Results at the left margin */
    return c;
}

int main (void)
{
    static char line[40];

    clrscr ();
#ifdef C40WIN
    printf ("A2LIB CSW TEST (%s, DOS 3.3)\n", c40_active () ? "40-COL WINDOW" : "VIDEOTERM");
#else
    printf ("A2LIB CSW TEST (VIDEOTERM, DOS 3.3)\n");
#endif
    printf ("START:        CSW=$%04X  DOS CSW=$%04X\n", csw (), dos_csw ());

    gotoxy (30, 14);
    mon_cout ('X');
    check ("COUT BEFORE INPUT ARRIVES", peek_at (30, 14) == 'X');

    gotoxy (0, 3);
    printf ("TYPE A WORD, PRESS RETURN:\n");
    fgets (line, sizeof (line), stdin);
    printf ("AFTER INPUT:  CSW=$%04X  DOS CSW=$%04X\n", csw (), dos_csw ());

    gotoxy (32, 14);
    mon_cout ('Y');
    check ("COUT AFTER INPUT ARRIVES", peek_at (32, 14) == 'Y');

    gotoxy (0, 9);
    printf ("%u FAILED. PRESS A KEY", failures);
    cgetc ();
    return 0;
}
