/*
** IP65 timer driver tests (DESIGN.md 6.3), linked with lib/a2lib-ip65.o
** ahead of IP65's libraries, then apple2-dos33.lib. Needs an Uthernet II
** in slot 3 and, at 10.0.2.2 (the emulated card's gateway to the host), a
** TCP server that echoes a line two seconds after reading it; it asks for
** the server's port. test/emutest.sh starts the server and runs this in
** real time, so the two seconds are real ones and the counted time can be
** held to them. Output fits a 40x24 screen.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <conio.h>
#include <a2timer.h>
#include <ip65.h>

#define MAX_SHOWN 12
#define DELAY_MS  2000          /* The server's delay before it echoes */
#define GIVE_UP   10000         /* Counted ms to wait for the echo */

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

static char line[16];
static char reply[16];
static unsigned char reply_len;
static volatile unsigned char echoed;

static void __fastcall__ received (const unsigned char* buf, int len)
{
    while (len > 0 && !echoed) {
        if (*buf == '\r') {
            echoed = 1;
        } else if (reply_len < sizeof (reply) - 1) {
            reply[reply_len++] = *buf;
        }
        ++buf;
        --len;
    }
}

/* Leases an address; returns nonzero if the stack is ready */
static unsigned char init_tests (void)
{
    unsigned char up;

    up = !ip65_init (ETH_INIT_DEFAULT);
    check ("Uthernet II in slot 3", up);
    if (up) {
        up = !dhcp_init ();
        check ("address leased", up && cfg_ip != 0);
    }
    return up;
}

/*
** Times the server's echo in counted milliseconds, polling as a program's
** own idle loop does: IP65, then one tick of the timer. Counted time stands
** still while IP65 runs, so it falls a little behind real time; the bounds
** allow for that. timer_read must follow the same count (it waits a tick
** and reports a2lib's milliseconds), where IP65's own driver would add 33
** ms per call, whatever time passed.
*/
static void echo_tests (unsigned port)
{
    unsigned long m0, d;
    unsigned t0, dt;
    unsigned char connected;

    connected = !tcp_connect (parse_dotted_quad ("10.0.2.2"), port, received);
    check ("connected to 10.0.2.2", connected);
    if (!connected) {
        return;
    }
    check ("line sent", !tcp_send ((const unsigned char*) "A2LIB\r", 6));
    t0 = timer_read ();
    m0 = a2_millis ();
    while (!echoed && a2_millis () - m0 < GIVE_UP) {
        ip65_process ();
        a2_idle ();
    }
    d = a2_millis () - m0;
    dt = timer_read () - t0;
    printf ("  counted %lu ms, timer_read %u\n", d, dt);
    reply[reply_len] = '\0';
    check ("line echoed", echoed && strcmp (reply, "A2LIB") == 0);
    check ("2 s delay counted as 1.5-2.6 s", d >= 1500 && d <= 2600);
    check ("timer_read follows a2_millis", dt >= d && dt <= d + 16);
    tcp_close ();
}

int main (void)
{
    unsigned port;

    printf ("\nA2LIB NETWORK TESTS\n");
    printf ("SERVER PORT:\n");
    fgets (line, sizeof (line), stdin);
    port = atoi (line);
    if (init_tests ()) {
        group ("INIT");
        echo_tests (port);
        group ("ECHO");
    } else {
        group ("INIT");
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
