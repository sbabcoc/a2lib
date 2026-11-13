/*
** sim65 regression test for the 40-column window's position gauge
** (DESIGN.md 6.3), run by "make simtest". Links the real win.s and timer
** modules, built for sim65 at $0C00 (sim0c00.cfg) so that the text screen
** at $0400 is free, and checks what the gauge leaves on the screen.
*/

#include <stdio.h>
#include <string.h>
#include <c40win.h>
#include <a2timer.h>

void tick (void);
static unsigned char fails;
static void check (const char* what, int ok)
{
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++fails;
}
static int corner_is (const char* text, unsigned char inverse)
{
    unsigned char i, c;
    for (i = 0; i < 10; ++i) {
        c = *(unsigned char*) (0x400 + 30 + i);
        if (c != (inverse ? text[i] & 0x3F : text[i] | 0x80)) return 0;
    }
    return 1;
}
static void ticks (unsigned n) { while (n--) tick (); }

int main (void)
{
    check ("no gauge at start", !corner_is ("[====....]", 1));
    c40_pan (40);
    check ("pan 40: [....====]", corner_is ("[....====]", 1));
    ticks (200);
    check ("still shown at 0.77 s", corner_is ("[....====]", 1));
    ticks (70);
    check ("hidden after 1 s", corner_is ("          ", 0));
    c40_pan (20);
    check ("pan 20: [..====..]", corner_is ("[..====..]", 1));
    ticks (200);
    c40_pan (0);
    check ("pan 0: [====....]", corner_is ("[====....]", 1));
    ticks (200);
    check ("restarted by second pan", corner_is ("[====....]", 1));
    ticks (70);
    check ("hidden 1 s after last pan", corner_is ("          ", 0));
    c40_follow ();
    check ("follow, no move: no gauge", corner_is ("          ", 0));
    printf ("%u FAILED\n", fails);
    return fails;
}
