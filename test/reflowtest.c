/*
** Reflow filter tests (DESIGN.md 3.7). Built three times:
**   reflowtest  apple2-dos33.lib (stock 40-column screen)
**   reflowvt    apple2-dos33-vt.lib (VideoTerm, 80 columns; stock without)
**   reflowwin   apple2-dos33-vtwin.lib, C40WIN (40-column window without
**               the VideoTerm)
** Each check prints through the filter, then reads the screen back with
** cpeekc. W is the visible width; reflowed lines hold at most W - 1.
*/

#include <stdio.h>
#include <string.h>
#include <conio.h>
#include <a2reflow.h>
#ifdef C40WIN
#include <c40win.h>
#endif

#define MAX_CHECKS 10

static const char* names[MAX_CHECKS];
static unsigned char results[MAX_CHECKS], total, passed;
static unsigned char W;         /* Visible width */

static void check (const char* what, int ok)
{
    if (total < MAX_CHECKS) {
        names[total] = what;
        results[total] = ok != 0;
    }
    ++total;
    if (ok) ++passed;
}

static char peek_at (unsigned char x, unsigned char y)
{
    gotoxy (x, y);
    return cpeekc ();
}

static const char text[] =
    "IT WAS THE BEST OF TIMES, IT WAS THE WORST OF TIMES, IT WAS THE AGE "
    "OF WISDOM, IT WAS THE AGE OF FOOLISHNESS, IT WAS THE EPOCH OF BELIEF, "
    "IT WAS THE EPOCH OF INCREDULITY, IT WAS THE SEASON OF LIGHT, IT WAS "
    "THE SEASON OF DARKNESS.";

/* Read rows 0..n back and compare their words, in order, with text; also
** check that no row reaches column W - 1. */
static int paragraph_ok (void)
{
    static char got[400];
    static char want[400];
    unsigned len = 0;
    unsigned char x, y, c, space = 1;
    const char* p;

    for (y = 0; y < 20; ++y) {
        if (peek_at (W - 1, y) != ' ') return 0;        /* Line too long */
        for (x = 0; x < W - 1; ++x) {
            c = peek_at (x, y);
            if (c == ' ') {
                if (!space && len < sizeof (got) - 1) got[len++] = ' ';
                space = 1;
            } else if (len < sizeof (got) - 1) {
                got[len++] = c;
                space = 0;
            }
        }
        if (!space && len < sizeof (got) - 1) got[len++] = ' ';  /* Row end */
        space = 1;
    }
    while (len && got[len - 1] == ' ') --len;
    got[len] = 0;

    /* The same text with runs of spaces collapsed */
    len = 0; space = 1;
    for (p = text; *p; ++p) {
        if (*p == ' ') {
            if (!space) want[len++] = ' ';
            space = 1;
        } else {
            want[len++] = *p;
            space = 0;
        }
    }
    want[len] = 0;
    return strcmp (got, want) == 0;
}

int main (void)
{
    unsigned char h, i, win = 0;

    screensize (&W, &h);
#ifdef C40WIN
    if (c40_active ()) {
        W = 40;
        win = 1;
    }
#endif

    clrscr ();
    reflow_on (0);
    printf ("%s", text);
    reflow_off ();
    check ("PARAGRAPH: WORDS WHOLE, < W", paragraph_ok ());
#ifdef C40WIN
    if (win) check ("WINDOW DID NOT PAN", c40_left () == 0);
#endif

    clrscr ();
    reflow_on (0);
    for (i = 0; i < W - 7; ++i) putchar ('A');
    printf (" BCDEFG");
    reflow_off ();
    check ("WORD AT EDGE MOVES", peek_at (0, 1) == 'B' && peek_at (W - 7, 0) == ' ');

    clrscr ();
    for (i = 0; i < W - 7; ++i) putchar ('A');
    printf (" BCDEFG");
    check ("REFLOW_OFF: RAW OUTPUT", peek_at (W - 1, 0) == 'G');

    clrscr ();
    reflow_on (0);
    for (i = 0; i < W + 5; ++i) putchar ('X');
    reflow_off ();
    check ("LONG WORD BROKEN AT W-1",
           peek_at (W - 2, 0) == 'X' && peek_at (W - 1, 0) == ' '
           && peek_at (5, 1) == 'X' && peek_at (6, 1) == ' ');

    clrscr ();
    reflow_on (0);
    printf ("NAME?");
    check ("PROMPT SHOWN AT ONCE", peek_at (4, 0) == '?');
    reflow_off ();

    clrscr ();
    reflow_on (0);
    printf ("A\n   B");
    reflow_off ();
    check ("INDENT AFTER NEWLINE KEPT", peek_at (3, 1) == 'B');

    clrscr ();
    printf ("A2LIB REFLOW TESTS, W=%u%s\n", W, win ? " (WINDOW)" : "");
    for (i = 0; i < total && i < MAX_CHECKS; ++i) {
        printf ("%s %s\n", results[i] ? "PASS" : "FAIL", names[i]);
    }
    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    printf ("PRESS A KEY");
    cgetc ();
    return 0;
}
