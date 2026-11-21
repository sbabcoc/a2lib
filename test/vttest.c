/*
** Display backend tests (DESIGN.md 3.4-3.6).
**
** Built twice:
**   vttest   linked with a2lib-vt.lib: the VideoTerm, or the stock
**            40-column screen without one
**   wintest  (C40WIN defined) linked with a2lib-c40win.lib: the
**            VideoTerm, or the 40-column window onto 80 x 24 without one
**   s70test  (S70 defined) linked with a2lib-soft70.lib at $4000:
**            the VideoTerm, or Soft-70 without one
**
** The same checks run in every case, adjusted for the width and for
** lowercase (the 40-column screen of a II+ shows uppercase only). Each
** check reads the screen back with cpeekc, wherex and wherey. On 80-column
** screens (card, window or Soft-70), scrolling is checked; in the window
** and Soft-70, panning and the position gauge, by reading the screen
** itself (the text screen, or the hi-res page).
**
** The results are printed after the checks, followed by a wait for a key,
** since the display returns to 40 columns at exit. The cursor should be
** visible while waiting (cursor (1)).
*/

#include <stdio.h>
#include <string.h>
#include <conio.h>
#include <apple2.h>
#ifdef C40WIN
#include <c40win.h>
#include <a2timer.h>
#endif
#ifdef S70
#include <soft70.h>
#include <a2timer.h>
#endif

#define MAX_CHECKS 24

static const char* names[MAX_CHECKS];
static unsigned char results[MAX_CHECKS];
static unsigned char total, passed;
static char line[41];

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

#ifdef C40WIN
/* What the 40-column text screen (page 1) shows at a column and row */
static unsigned char screen_at (unsigned char x, unsigned char y)
{
    return *(unsigned char*) (0x400 + (y & 7) * 0x80 + (y >> 3) * 0x28 + x);
}

/* Whether row 0, columns 30-39 show the given text, in inverse (gauge) or
** normal video */
static unsigned char corner_is (const char* text, unsigned char inverse)
{
    unsigned char i;

    for (i = 0; i < 10; ++i) {
        if (screen_at (30 + i, 0) != (inverse ? text[i] & 0x3F : text[i] | 0x80)) {
            return 0;
        }
    }
    return 1;
}
#endif

#ifdef S70
/* The 4 pixels of each scanline of Soft-70's cell at a screen column and
** row, from the hi-res page */
static void cell_at (unsigned char x, unsigned char y, unsigned char bits[8])
{
    unsigned char k, sh = x * 4 % 7;
    unsigned char* p;
    unsigned v;

    for (k = 0; k < 8; ++k) {
        p = (unsigned char*) (0x2000 + (y & 7) * 0x80 + (y >> 3) * 0x28 + k * 0x400 + x * 4 / 7);
        v = p[0] | (unsigned) p[1] << 7;
        bits[k] = (v >> sh) & 0x0F;
    }
}

/* Whether two cells show the same pixels, and the first isn't blank */
static unsigned char same_cells (unsigned char x1, unsigned char y1,
                                 unsigned char x2, unsigned char y2)
{
    unsigned char a[8], b[8], k, any = 0;

    cell_at (x1, y1, a);
    cell_at (x2, y2, b);
    for (k = 0; k < 8; ++k) {
        if (a[k] != b[k]) return 0;
        any |= a[k];
    }
    return any != 0;
}

/* Whether the bottom scanline shows the gauge's bar for a position (track
** of alternate pixels, solid thumb over 35 bytes), or is blank */
static unsigned char bar_is (unsigned char left, unsigned char shown)
{
    unsigned char b, start = left >> 1, want;
    const unsigned char* line = (const unsigned char*) (0x2000 + 0x3D0 + 7 * 0x400);

    for (b = 0; b < 40; ++b) {
        want = !shown ? 0 : (b >= start && b < start + 35) ? 0x7F : (b & 1) ? 0x2A : 0x55;
        if (line[b] != want) return 0;
    }
    return 1;
}
#endif

int main (void)
{
    unsigned char w, h, vt, win, lower, twocol, i;

    screensize (&w, &h);
#if defined(C40WIN)
    win = c40_active ();
#elif defined(S70)
    win = s70_active ();
#else
    win = 0;
#endif
    vt = (w == 80 && !win);
#ifdef S70
    lower = 1;                  /* VideoTerm or Soft-70 */
#else
    lower = vt;
#endif

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
    check ("lowercase", peek_at (3, 6) == (lower ? 'q' : 'Q'));

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
    check ("stdio lowercase", peek_at (0, 19) == (lower ? 'l' : 'L'));

#ifdef C40WIN
    if (win) {
        /* Following pans in steps of 20 columns */
        gotoxy (60, 3);
        cputc ('Z');
        check ("follow pans right", c40_left () == 40 && screen_at (20, 3) == ('Z' | 0x80));

        /* The position gauge appears after a pan, and goes after a second */
        check ("gauge shown", corner_is ("[....====]", 1));
        {
            unsigned long m0 = a2_millis ();
            while (a2_millis () - m0 < 1100) {
                a2_idle ();
            }
        }
        check ("gauge hidden", corner_is ("          ", 0));
        gotoxy (5, 4);
        cputc ('Y');
        check ("follow pans left", c40_left () == 0 && screen_at (5, 4) == ('Y' | 0x80));

        /* c40_pan stops following; c40_follow resumes it */
        gotoxy (30, 3);
        cputc ('V');            /* Visible at column 10 once panned to 20 */
        c40_pan (20);
        gotoxy (70, 4);
        cputc ('W');
        check ("c40_pan stops follow", c40_left () == 20 && screen_at (10, 3) == ('V' | 0x80));
        c40_follow ();
        check ("c40_follow resumes", c40_left () == 40 && screen_at (30, 4) == ('W' | 0x80));
    }
#endif

#ifdef S70
    if (win) {
        /* Following pans between columns 0-69 and 10-79. The same letter
        ** drawn at another bit offset must show the same pixels. */
        gotoxy (12, 2);
        cputc ('Z');
        gotoxy (75, 3);
        cputc ('Z');
        check ("follow pans right", s70_left () == 10 && same_cells (65, 3, 2, 2));

        /* The position gauge appears after a pan, and goes after a second */
        check ("gauge shown", bar_is (10, 1));
        {
            unsigned long m0 = a2_millis ();
            while (a2_millis () - m0 < 1100) {
                a2_idle ();
            }
        }
        check ("gauge hidden", bar_is (10, 0));
        gotoxy (5, 4);
        cputc ('Z');
        check ("follow pans left", s70_left () == 0 && same_cells (5, 4, 12, 2));

        /* Inverse shows the complement of the cell */
        gotoxy (20, 4);
        revers (1);
        cputc ('Z');
        revers (0);
        {
            unsigned char a[8], b[8], k, ok = 1;
            cell_at (20, 4, a);
            cell_at (5, 4, b);
            for (k = 0; k < 8; ++k) {
                if (a[k] != (b[k] ^ 0x0F)) ok = 0;
            }
            check ("inverse", ok && peek_at (20, 4) == 'Z');
        }

        /* s70_pan stops following; s70_follow resumes it */
        s70_pan (10);
        gotoxy (2, 4);
        cputc ('W');
        check ("s70_pan stops follow", s70_left () == 10);
        s70_follow ();
        check ("s70_follow resumes", s70_left () == 0);
    }
#endif

    if (w == 80) {
        /* A line feed on the last row scrolls (card and window alike) */
        gotoxy (0, 1);
        cputc ('M');
        gotoxy (0, 23);
        cputc ('\n');
        check ("LF scrolls at bottom", wherey () == 23 && peek_at (0, 0) == 'M');
    }

    /* Results */
    clrscr ();
    printf ("A2LIB DISPLAY TESTS: %s\n",
            vt ? "VIDEOTERM 80 COLUMNS" :
#ifdef S70
            win ? "SOFT-70" :
#endif
            win ? "40-COLUMN WINDOW" : "40 COLUMNS");
    /* Two columns where 70 or more are visible, so that the results fit */
#ifdef C40WIN
    twocol = vt;
#else
    twocol = (w == 80);
#endif
    for (i = 0; i < total && i < MAX_CHECKS; ++i) {
        sprintf (line, "%s %s", results[i] ? "PASS" : "FAIL", names[i]);
        if (twocol && !(i & 1)) {
            printf ("%-40s", line);
        } else {
            printf ("%s\n", line);
        }
    }
    if (twocol && (i & 1)) {
        printf ("\n");
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
