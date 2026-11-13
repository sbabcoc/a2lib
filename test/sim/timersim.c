/*
** sim65 regression test for the cooperative timer and software clock
** (DESIGN.md 6.3), run by "make simtest". Links the real timer.s, tick.s,
** kbhit.s, gettime.s and settime.s, built for sim65, and checks the
** Bresenham arithmetic against an exact model, ms-to-tick conversion,
** one-shot and periodic timers, slots, zero-page preservation and the
** clock; it also reports a2_tick's measured cycle cost (the tick-length
** constant in timer.inc assumes about 87.5 cycles including JSR and RTS).
*/

#include <stdio.h>
#include <time.h>
#include <a2timer.h>

void tick (void);
unsigned cyc_empty (void);
unsigned cyc_tick (void);
unsigned char zp_check (void);
unsigned char zp_fired;
static unsigned char fails;
static unsigned count;
static unsigned long fired_tick, ticks;
static char scratch[16];

static void check (const char* what, int ok)
{
    printf ("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) ++fails;
}
static void counter (void) { ++count; fired_tick = ticks; }
static void zp_cb (void) { sprintf (scratch, "%lu", a2_millis ()); zp_fired = 1; }
static void run (unsigned long n) { while (n--) { ++ticks; tick (); } }

int main (void)
{
    unsigned long m0, cyc = 0, base;
    unsigned i, err = 0, ms = 0, d;
    unsigned char h[5], ok;
    struct timespec ts;

    /* Bresenham: compare with an exact model over 2 * 187 ticks */
    ok = 1;
    for (i = 0; i < 374; ++i) {
        m0 = a2_millis ();
        tick ();
        d = (unsigned) (a2_millis () - m0);
        if (err < 187 - 160) { err += 160; ms = 3; } else { err -= 27; ms = 4; }
        ok &= (d == ms);
    }
    check ("Bresenham matches model", ok);
    m0 = a2_millis (); run (1000); d = (unsigned) (a2_millis () - m0);
    printf ("     1000 ticks = %u ms\n", d);
    check ("1000 ticks = 3855-3856 ms", d >= 3855 && d <= 3856);

    /* Cycle cost of a JSR a2_tick, common path, averaged over 1870 ticks */
    base = cyc_empty ();
    for (i = 0; i < 1870; ++i) cyc += cyc_tick () - base;
    printf ("     a2_tick avg cycles incl JSR/RTS: %lu.%lu\n", cyc / 1870, (cyc % 1870) * 10 / 1870);

    /* ms -> ticks and one-shot */
    count = 0; ticks = 0;
    h[0] = a2_timer_start (100, counter, 0);
    run (40);
    printf ("     100 ms one-shot fired at tick %lu\n", fired_tick);
    check ("one-shot fires once at tick 26", count == 1 && fired_tick == 26);

    count = 0; ticks = 0;
    h[0] = a2_timer_start (50, counter, 1);
    run (131);
    check ("periodic 13 ticks: 10 in 131", count == 10);
    a2_timer_stop (h[0]);
    run (100);
    check ("stop", count == 10);

    ok = 1;
    for (i = 0; i < 4; ++i) { h[i] = a2_timer_start (1000, counter, 0); ok &= h[i] != A2_TIMER_NONE; }
    check ("4 slots", ok);
    check ("5th fails", a2_timer_start (1000, counter, 0) == A2_TIMER_NONE);
    for (i = 0; i < 4; ++i) a2_timer_stop (h[i]);
    check ("0 ms = 1 tick", (count = 0, ticks = 0, a2_timer_start (0, counter, 0), run (3), fired_tick == 1));
    check ("65535 ms accepted", (h[0] = a2_timer_start (65535U, counter, 0)) != A2_TIMER_NONE);
    a2_timer_stop (h[0]);

    /* Cycle cost with one active timer */
    h[0] = a2_timer_start (60000U, counter, 1);
    cyc = 0; for (i = 0; i < 1870; ++i) cyc += cyc_tick () - base;
    printf ("     ... with 1 active timer: %lu.%lu\n", cyc / 1870, (cyc % 1870) * 10 / 1870);
    a2_timer_stop (h[0]);

    zp_fired = 0;
    a2_timer_start (20, zp_cb, 0);
    check ("zero page preserved (kbhit)", zp_check ());

    /* Clock */
    check ("unset", a2_clock_age () == A2_CLOCK_UNSET);
    clock_gettime (CLOCK_REALTIME, &ts);
    check ("unset = up-time", ts.tv_sec * 1000 + ts.tv_nsec / 1000000 == a2_millis ());
    printf ("     up-time %lu s + %lu ns, millis %lu\n", ts.tv_sec, ts.tv_nsec, a2_millis ());
    ts.tv_sec = 1000000000UL; ts.tv_nsec = 0;
    check ("settime", clock_settime (CLOCK_REALTIME, &ts) == 0);
    clock_gettime (CLOCK_REALTIME, &ts);
    check ("set", ts.tv_sec == 1000000000UL && a2_clock_age () == 0);
    run (300);
    check ("advances", a2_clock_age () == 1 && time (NULL) == 1000000001UL);

    printf ("%u FAILED\n", fails);
    return fails;
}
