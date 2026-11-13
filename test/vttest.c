/*
** Display backend tests (DESIGN.md 3.4), linked with apple2-dos33-vt.lib.
**
** With a VideoTerm in slot 3, the conio functions and stdio drive the card
** (80 x 24); without one, the stock 40-column code. The same checks run in
** both cases, adjusted for the width and for lowercase (the 40-column
** screen of a II+ shows uppercase only). Each check reads the screen back
** with cpeekc, wherex and wherey.
**
** The results are printed after the checks, followed by a wait for a key,
** since the display returns to 40 columns at exit. The cursor should be
** visible while waiting (cursor (1)).
*/

#include <stdio.h>
#include <string.h>
#include <conio.h>
#include <apple2.h>

#define MAX_CHECKS 20

static const char* names[MAX_CHECKS];
static unsigned char results[MAX_CHECKS];
static unsigned char total, passed;

static void check (const char* what, int ok)
{
    if (total < MAX_CHECKS) {
        names[total] = what;
        results[total] = ok != 0;
    }
    ++total;
    if (ok) {
        ++passed;
    }
}

static char peek_at (unsigned char x, unsigned char y)
{
    gotoxy (x, y);
    return cpeekc ();
}

int main (void)
{
    unsigned char w, h, vt, i;

    screensize (&w, &h);
    vt = (w == 80);

    check ("screen size", h == 24 && (w == 80 || w == 40));

    clrscr ();
    check ("clrscr homes", wherex () == 0 && wherey () == 0);

    cputs ("HELLO");
    check ("cputs advances", wherex () == 5 && wherey () == 0);
    check ("cpeekc", peek_at (1, 0) == 'E');

    gotoxy (10, 5);
    cputc ('X');
    check ("gotoxy, cputc", peek_at (10, 5) == 'X' && wherey () == 5);

    gotoxy (3, 6);
    cputc ('q');
    check ("lowercase", peek_at (3, 6) == (vt ? 'q' : 'Q'));

    gotoxy (7, 8);
    cputc ('\r');
    check ("CR to column 0", wherex () == 0 && wherey () == 8);

    gotoxy (7, 8);
    cputc ('\n');
    check ("LF keeps column", wherex () == 7 && wherey () == 9);

    chlinexy (0, 10, 3);
    check ("chline", peek_at (1, 10) == CH_HLINE);

    cvlinexy (20, 11, 3);
    check ("cvline", peek_at (20, 12) == CH_VLINE && peek_at (20, 13) == CH_VLINE);

    gotoxy (w - 2, 14);
    cputs ("ABC");
    check ("wrap at last column", peek_at (w - 1, 14) == 'B' && peek_at (0, 15) == 'C');

    gotoxy (5, 16);
    gotox (9);
    check ("gotox keeps row", wherex () == 9 && wherey () == 16);
    gotoy (17);
    check ("gotoy keeps column", wherex () == 9 && wherey () == 17);

    gotoxy (30, 18);
    printf ("P");
    check ("stdio at conio cursor", peek_at (30, 18) == 'P');

    gotoxy (0, 19);
    printf ("lc");
    check ("stdio lowercase", peek_at (0, 19) == (vt ? 'l' : 'L'));

    /* Results */
    clrscr ();
    printf ("A2LIB DISPLAY TESTS: %s\n", vt ? "VIDEOTERM 80 COLUMNS" : "40 COLUMNS");
    for (i = 0; i < total && i < MAX_CHECKS; ++i) {
        printf ("%s %s\n", results[i] ? "PASS" : "FAIL", names[i]);
    }
    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    printf ("PRESS A KEY");
    cursor (1);
    cgetc ();
    cursor (0);
    return 0;
}
