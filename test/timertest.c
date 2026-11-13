/*
** Cooperative timer and software clock tests (DESIGN.md 6.3), linked with
** apple2-dos33.lib. Run under DOS 3.3 without touching the keyboard until
** the INPUT group asks for a line. Output fits a 40x24 screen.
*/

#include <stdio.h>
#include <string.h>
#include <time.h>
#include <conio.h>
#include <a2timer.h>

#define MAX_SHOWN 12

static unsigned char passed, total, gpassed, gtotal, shown;

static void check (const char* what, int ok)
{
    ++gtotal;
    if (ok) {
        ++gpassed;
    } else if (shown < MAX_SHOWN) {
        printf ("  FAIL %s\n", what);
        ++shown;
    }
}

static void group (const char* name)
{
    printf ("%-32s%2u/%u\n", name, gpassed, gtotal);
    passed += gpassed;
    total += gtotal;
    gpassed = gtotal = 0;
}

/* Poll kbhit (a polling point) for ms milliseconds of counted time */
static void poll_for (unsigned ms)
{
    unsigned long until = a2_millis () + ms;

    while (a2_millis () < until) {
        kbhit ();
    }
}

static volatile unsigned char count;
static unsigned long fired_at;
static char scratch[16];

static void counter (void)
{
    ++count;
    fired_at = a2_millis ();
}

unsigned char zp_fired;
unsigned char zp_check (void);

static void zp_cb (void)
{
    sprintf (scratch, "%lu", a2_millis ());     /* Uses the C zero page */
    zp_fired = 1;
}

static void tick_tests (void)
{
    unsigned long m0, d;
    unsigned i;

    m0 = a2_millis ();
    for (i = 0; i < 1000; ++i) {
        a2_idle ();
    }
    d = a2_millis () - m0;
    check ("1000 ticks = 3855-3856 ms", d >= 3855 && d <= 3856);

    m0 = a2_millis ();
    for (i = 0; i < 20000; ++i) {
        scratch[i & 7] = i;                     /* Computing, no polling */
    }
    check ("stands still while computing", a2_millis () == m0);

    m0 = a2_millis ();
    for (i = 0; i < 100; ++i) {
        kbhit ();
    }
    d = a2_millis () - m0;
    check ("kbhit counts a tick", d >= 385 && d <= 386);
}

static void timer_tests (void)
{
    unsigned char h[5], i, ok;
    unsigned long start;

    count = 0;
    start = a2_millis ();
    h[0] = a2_timer_start (100, counter, 0);
    check ("one-shot starts", h[0] != A2_TIMER_NONE);
    poll_for (300);
    check ("one-shot fires once", count == 1);
    check ("one-shot after 100 ms", fired_at - start >= 97 && fired_at - start <= 104);

    count = 0;
    h[0] = a2_timer_start (50, counter, 1);
    poll_for (520);
    check ("periodic 50 ms: 9-11 in 520", count >= 9 && count <= 11);
    a2_timer_stop (h[0]);
    i = count;
    poll_for (200);
    check ("stop", count == i);

    ok = 1;
    for (i = 0; i < 4; ++i) {
        h[i] = a2_timer_start (1000, counter, 0);
        ok &= h[i] != A2_TIMER_NONE;
    }
    check ("4 slots", ok);
    h[4] = a2_timer_start (1000, counter, 0);
    check ("5th fails", h[4] == A2_TIMER_NONE);
    for (i = 0; i < 4; ++i) {
        a2_timer_stop (h[i]);
    }

    zp_fired = 0;
    a2_timer_start (20, zp_cb, 0);
    check ("zero page preserved", zp_check ());
}

static void clock_tests (void)
{
    struct timespec ts;

    check ("unset", a2_clock_age () == A2_CLOCK_UNSET);
    clock_gettime (CLOCK_REALTIME, &ts);
    check ("unset = up-time",
           ts.tv_sec * 1000 + ts.tv_nsec / 1000000 == a2_millis ());

    ts.tv_sec = 1000000000UL;
    ts.tv_nsec = 0;
    check ("settime", clock_settime (CLOCK_REALTIME, &ts) == 0);
    clock_gettime (CLOCK_REALTIME, &ts);
    check ("set", ts.tv_sec == 1000000000UL && a2_clock_age () == 0);
    poll_for (1100);
    check ("advances", a2_clock_age () >= 1 && time (NULL) >= 1000000001UL);
}

static void input_test (void)
{
    static char line[40];
    unsigned char h;
    unsigned long m0;

    count = 0;
    m0 = a2_millis ();
    h = a2_timer_start (100, counter, 1);
    printf ("TYPE A WORD, PRESS RETURN:\n");
    fgets (line, sizeof (line), stdin);
    a2_timer_stop (h);
    check ("callbacks during input", count > 0);
    check ("time counted during input", a2_millis () - m0 >= 100);
    check ("line read intact", strlen (line) > 1 && line[strlen (line) - 1] == '\n');
}

int main (void)
{
    printf ("\nA2LIB TIMER TESTS\n");
    tick_tests ();      group ("TICKS");
    timer_tests ();     group ("TIMERS");
    clock_tests ();     group ("CLOCK");
    input_test ();      group ("INPUT");
    if (passed == total) {
        printf ("ALL %u PASSED\n", total);
    } else {
        printf ("%u OF %u FAILED\n", total - passed, total);
    }
    return 0;
}
