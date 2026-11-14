/*
** sim65 regression test for the reflow filter (DESIGN.md 3.7), run by
** "make simtest". Links the real reflow.s with stubs that record what the
** filter sends to the screen (reflowshim.s), renders that onto a model
** screen (CR: next line; backspace: back a column; others: written at the
** column), and compares the lines, with trailing blanks removed, against
** wrapping worked out by hand.
*/

#include <stdio.h>
#include <string.h>
#include <a2reflow.h>

extern unsigned char out_buf[];
extern unsigned out_len;
extern unsigned char stub_view, stub_x;
void __fastcall__ put (char c);
unsigned char __fastcall__ put_regs (char c);

#define ROWS 8
static char screen[ROWS][82];
static unsigned char fails;

static void check (const char* what, int ok)
{
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++fails;
}

static void start (unsigned char width, unsigned char x)
{
    stub_x = x;
    out_len = 0;
    reflow_on (width);
}

static void puts_raw (const char* s)
{
    while (*s) put (*s++);
}

/* Render the recorded output, starting at column x0, and compare */
static int lines_are (unsigned char x0, const char* const* want, unsigned char n)
{
    unsigned i, row = 0, col = x0, len;
    unsigned char c;

    memset (screen, ' ', sizeof (screen));
    for (i = 0; i < out_len; ++i) {
        c = out_buf[i] & 0x7F;
        if (c == '\r') {
            ++row; col = 0;
        } else if (c == 8) {
            if (col) --col;
        } else if (c >= ' ' && row < ROWS && col < 81) {
            screen[row][col++] = c;
        }
    }
    for (i = 0; i < ROWS; ++i) {
        len = 81;
        while (len && screen[i][len - 1] == ' ') --len;
        screen[i][len] = 0;
    }
    for (i = 0; i < ROWS; ++i) {
        if (strcmp (screen[i], i < n ? want[i] : "") != 0) {
            printf ("     row %u: \"%s\"\n", i, screen[i]);
            return 0;
        }
    }
    return 1;
}

int main (void)
{
    static const char* const a[] = { "THE QUICK", "BROWN FOX", "JUMPS OVER", "THE LAZY", "DOG" };
    static const char* const b[] = { "ABCDE", "FGHIJ", "KL MN" };
    static const char* const c[] = { "AAAA", "BBB", "CC", "  DD" };
    static const char* const d[] = { "ABCDE", "FG" };
    static const char* const e[] = { "     HELLO", "WORLD" };
    static const char* const f[] = { "AC" };
    static const char* const g[] = { "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "B" };
    static const char* const h[] = { "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "B" };
    static const char* const k[] = { "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "B" };
    unsigned char i;

    start (12, 0); puts_raw ("THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG");
    check ("greedy wrap, width 12", lines_are (0, a, 5));

    start (6, 0); puts_raw ("ABCDEFGHIJKL MN");
    check ("word longer than a line is broken", lines_are (0, b, 3));

    start (8, 0); puts_raw ("AAAA BBB   CC\r  DD");
    check ("moved words; indentation after CR kept", lines_are (0, c, 4));

    start (6, 0); puts_raw ("ABCDE  FG");
    check ("space ends full line; leading space dropped", lines_are (0, d, 2));

    start (12, 5); puts_raw ("HELLO WORLD");
    check ("starts at the cursor's column", lines_are (5, e, 2));

    start (12, 0); puts_raw ("AB\bC");
    check ("backspace", lines_are (0, f, 1));

    stub_view = 40;
    start (0, 0); for (i = 0; i < 39; ++i) put ('A'); puts_raw (" B");
    check ("width 0 = viewport (40): 39 per line", lines_are (0, g, 2));
    start (0, 0); for (i = 0; i < 38; ++i) put ('A'); puts_raw (" B");
    check ("never writes column 39", lines_are (0, h, 2));

    stub_view = 80;
    start (0, 0); for (i = 0; i < 79; ++i) put ('A'); puts_raw (" B");
    check ("viewport 80: 79 per line", lines_are (0, k, 2));

    start (6, 0);
    check ("COUT preserves A, X, Y (filter)", put_regs ('Q') && put_regs (' ') && put_regs ('\r'));

    reflow_off ();
    out_len = 0; puts_raw ("ABCDEFGH IJ\r");
    check ("reflow_off passes through", out_len == 12 && memcmp (out_buf, "\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xA0\xC9\xCA\x8D", 12) == 0);

    printf ("%u FAILED\n", fails);
    return fails;
}
