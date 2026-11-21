/*
** sim65 regression test for Soft-70 (DESIGN.md 3.8), run by "make
** simtest". Links the real model (libsrc/s80) and Soft-70 display
** (libsrc/s70) and timer modules, built for sim65 with the Apple II
** layout (sim4000.cfg), and checks that the hi-res page always shows
** what the model holds.
**
** The check renders the model's buffer (s80_buf, from s80_left) with the
** font in use into scanline bytes and compares them with the page. The
** only difference allowed is the position gauge's bar, which is either
** absent or exactly right for the current position. A long run of random
** conio operations (characters, controls, cursor moves, inverse, scrolls,
** pans, clears, font changes, the cursor, timer ticks) is checked as it
** goes. Cycle counts for drawing, scrolling and panning are reported.
*/

#include <stdio.h>
#include <string.h>
#include <conio.h>
#include <sim65.h>
#include <soft70.h>

void tick (void);
void s70_curshow (void);
void s70_curhide (void);
extern unsigned char s80_buf[24][80];
extern unsigned char* s80_left_addr;
void run_destructors (void);

#define INVFLG (*(unsigned char*) 0x32)
#define PAGE ((unsigned char*) 0x2000)

static unsigned char fails;
static void check (const char* what, int ok)
{
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++fails;
}

static unsigned long seed = 4321;
static unsigned rnd (void)
{
    seed = seed * 1103515245UL + 12345;
    return (unsigned) (seed >> 16) & 0x7FFF;
}

/* The fonts: the default font's 'A', and two random fonts in one merged
** file (font A in the low nibbles, font B in the high) */
static const unsigned char glyph_A[8] = { 4, 10, 10, 14, 10, 10, 10, 0 };
static unsigned char merged[768];
static unsigned char font[768];         /* The font in use, as expected */

static void use_font (unsigned char nibble)
{
    unsigned i;
    s70_font (merged, nibble);
    for (i = 0; i < 768; ++i) {
        font[i] = (nibble ? merged[i] >> 4 : merged[i]) & 0x0F;
    }
    memset (font, 0, 8);                /* Space is always blank */
}

static unsigned char line[8][40];

static unsigned char* rowaddr (unsigned char r, unsigned char k)
{
    return PAGE + (r & 7) * 0x80 + (r >> 3) * 0x28 + k * 0x400;
}

static unsigned char bar[40];
static void bar_for (unsigned char left)
{
    unsigned char b, start = left >> 1;
    for (b = 0; b < 40; ++b) {
        bar[b] = (b >= start && b < start + 35) ? 0x7F : (b & 1) ? 0x2A : 0x55;
    }
}

/* Whether the page shows the model, allowing the gauge's bar */
static const char* why;
static int barshown;                    /* After screen_ok: the bar is shown */
static int screen_ok (void)
{
    unsigned char r, c, k, code, g, inv, sh, b, left = s70_left ();
    unsigned v;
    unsigned char* p;

    barshown = -1;

    for (r = 0; r < 24; ++r) {
        memset (line, 0, sizeof line);
        for (c = 0; c < 70; ++c) {
            code = s80_buf[r][c + left] ^ 0xA0;
            g = code & 0x7F;
            if (g < 0x20) g += 0x40;
            g -= 0x20;
            inv = (code & 0x80) ? 0 : 0x0F;
            if (g == 0 && !inv) continue;
            b = c * 4 / 7;
            sh = c * 4 % 7;
            for (k = 0; k < 8; ++k) {
                v = (unsigned) ((font[g * 8 + k] ^ inv) & 0x0F) << sh;
                line[k][b] |= v & 0x7F;
                if (v >> 7) line[k][b + 1] |= v >> 7;
            }
        }
        for (k = 0; k < 8; ++k) {
            p = rowaddr (r, k);
            if (r == 23 && k == 7) {
                bar_for (left);
                for (b = 0; b < 40; ++b) {
                    unsigned char d = p[b] ^ line[k][b];
                    if (barshown < 0) barshown = (d != 0);
                    if (d != (barshown ? bar[b] : 0)) { why = "bottom scanline"; return 0; }
                }
            } else if (memcmp (p, line[k], 40) != 0) {
                why = "text";
                return 0;
            }
        }
    }
    return 1;
}

/* No byte of the page has bit 7 set, holes included */
static int bit7_clear (void)
{
    unsigned i;
    for (i = 0; i < 0x2000; ++i) {
        if (PAGE[i] & 0x80) return 0;
    }
    return 1;
}

static unsigned long cycles (void)
{
    peripherals.counter.latch = 0;
    peripherals.counter.select = COUNTER_SELECT_CLOCKCYCLE_COUNTER;
    return peripherals.counter.value32[0];
}

static const char fox[] = "The quick brown fox jumps over the lazy dog, again and again and again. ";

int main (void)
{
    unsigned i, step, n, op, bad = 0, checks = 0;
    unsigned char k, ok;
    unsigned long t0, t;

    INVFLG = 0xFF;

    /* The text marker (DESIGN.md 3.9), directly before the buffer */
    {
        const unsigned char* m = (const unsigned char*) s80_buf - 16;
        check ("text marker",
               memcmp (m, "A2SCR80", 7) == 0 && m[7] == 1
               && m[8] == 80 && m[9] == 24 && m[10] == 70 && m[11] == 1
               && *(unsigned char**) (m + 12) == s80_left_addr
               && *(void**) (m + 14) == (void*) s80_buf);
    }

    /* The default font, and the cell layout */
    clrscr ();
    cputc ('A');
    for (ok = 1, k = 0; k < 8; ++k) {
        if (*rowaddr (0, k) != glyph_A[k]) ok = 0;
    }
    check ("default font: 'A' at column 0", ok);

    for (i = 0; i < 768; ++i) {
        merged[i] = rnd () & 0xFF;
    }
    use_font (0);
    check ("font A (low nibbles) redrawn", screen_ok ());
    use_font (1);
    check ("font B (high nibbles) redrawn", screen_ok ());

    /* Every phase of the cell layout, normal and inverse */
    clrscr ();
    for (i = 0; i < 70; ++i) cputc (0x21 + i % 94);
    INVFLG = 0x3F;
    for (i = 0; i < 70; ++i) cputc (0x21 + i % 94);
    INVFLG = 0x7F;                      /* Flashing: shown inverse */
    for (i = 0; i < 70; ++i) cputc ('a' + i % 26);
    INVFLG = 0xFF;
    check ("70 columns, normal, inverse, flashing", screen_ok ());

    /* Random operations */
    for (step = 0; step < 4000; ++step) {
        op = rnd () % 220;
        if (op < 120) cputc (0x20 + rnd () % 95);
        else if (op < 130) cputc ('\r');
        else if (op < 140) cputc ('\n');
        else if (op < 150) gotoxy (rnd () % 85, rnd () % 26);
        else if (op < 156) INVFLG = (rnd () % 3 == 0) ? 0x3F : (rnd () & 1) ? 0x7F : 0xFF;
        else if (op < 159) s70_pan (rnd () % 14);
        else if (op < 162) s70_follow ();
        else if (op < 163) clrscr ();
        else if (op < 171) { for (n = rnd () % 300; n; --n) tick (); }
        else if (op < 181) cputs (fox);
        else if (op < 186) gotox (rnd () % 82);
        else if (op < 191) gotoy (rnd () % 25);
        else if (op < 193) use_font (rnd () & 1);
        else if (op < 198) {
            s70_curshow ();
            for (n = rnd () % 200; n; --n) tick ();
            s70_curhide ();
            for (n = rnd () % 100; n; --n) tick ();
        }
        else cputc (rnd () % 32);
        if (step % 40 == 39) {
            ++checks;
            if (!screen_ok ()) {
                if (!bad) printf ("  first mismatch at step %u (%s)\n", step, why);
                ++bad;
            }
        }
    }
    printf ("  %u checks\n", checks);
    check ("page matches the model after random operations", bad == 0);
    check ("bit 7 clear throughout", bit7_clear ());
    /* The position gauge: shown after a pan, gone a second after the last
    ** (a tick is 3.86 ms: 200 ticks 0.77 s, 270 ticks 1.04 s) */
    s70_pan (0);
    for (n = 300; n; --n) tick ();
    check ("no gauge a second after a pan", screen_ok () && barshown == 0);
    s70_pan (10);
    check ("gauge shown after a pan", screen_ok () && barshown == 1);
    for (n = 200; n; --n) tick ();
    check ("gauge still shown at 0.77 s", screen_ok () && barshown == 1);
    for (n = 70; n; --n) tick ();
    check ("gauge gone after a second", screen_ok () && barshown == 0);
    s70_pan (0);
    for (n = 200; n; --n) tick ();
    s70_pan (10);
    for (n = 200; n; --n) tick ();
    check ("gauge restarted by a second pan", screen_ok () && barshown == 1);
    for (n = 70; n; --n) tick ();
    check ("gauge gone a second after the last pan", screen_ok () && barshown == 0);
    gotoxy (20, 5);             /* Visible at either position */
    s70_follow ();
    check ("follow without a move: no gauge", screen_ok () && barshown == 0);

    /* Time as before these checks: not following, at column 10, no gauge */
    s70_pan (10);
    for (n = 270; n; --n) tick ();

    /* Timing, reported */
    INVFLG = 0xFF;
    use_font (0);
    clrscr ();
    gotoxy (0, 5);
    t0 = cycles ();
    for (i = 0; i < 70; ++i) cputc ('m');
    t = cycles () - t0;
    printf ("  cputc: %lu cycles per character\n", t / 70);

    clrscr ();
    for (i = 0; i < 24; ++i) {
        gotoxy (0, i);
        cputs ("Seventy columns of text, every row full, to time the slowest case..");
    }
    gotoxy (0, 23);
    t0 = cycles ();
    cputc ('\n');
    t = cycles () - t0;
    printf ("  scroll, 70 columns in every row: %lu cycles\n", t);
    check ("page matches after full scroll", screen_ok ());

    clrscr ();
    for (i = 0; i < 24; ++i) {
        gotoxy (0, i);
        cputs ("About forty characters on each row....");
    }
    gotoxy (0, 23);
    t0 = cycles ();
    cputc ('\n');
    t = cycles () - t0;
    printf ("  scroll, 38 columns in every row: %lu cycles\n", t);

    clrscr ();
    for (i = 0; i < 24; ++i) {
        gotoxy (0, i);
        cputs ("Seventy columns of text, every row full, to time the slowest case..");
    }
    t0 = cycles ();
    s70_pan (10);
    t = cycles () - t0;
    printf ("  pan, 69 columns in every row: %lu cycles\n", t);
    check ("page matches after pan", screen_ok ());

    run_destructors ();
    check ("no text marker after exit", *((unsigned char*) s80_buf - 16) == 0);

    printf ("%u FAILED\n", fails);
    return fails;
}
