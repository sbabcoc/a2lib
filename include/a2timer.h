/*
** a2timer.h: cooperative timer and software clock (a2lib)
**
** A stock Apple II+ has no timer hardware, so time advances only while a
** program waits inside the library: in cgetc, kbhit, stdio input, a2_idle,
** and (with lib/a2lib-ip65.o) IP65's timer_read. While a program computes
** without calling these, the count stands still. One tick is about
** 3.86 ms (NTSC Apple II+). For details, see section 6.3 of DESIGN.
**
** Link lib/a2lib-timer.o and lib/a2lib-timer.lib ahead of
** lib/a2lib-dos33.lib. a2lib-soft70 includes the timer, which its gauge
** and cursor use, so with it only the clock (time, clock_gettime,
** clock_settime) needs the timer library; a2lib-vt doesn't.
**
** Timer callbacks run inside those waits. They must be short, may use
** conio and stdio output, and must not wait for keys (cgetc, stdio input),
** call a2_idle, or call IP65. The C runtime's zero page and the monitor's
** cursor (CH, CV, BASL, INVFLG) are saved and restored around them; on
** the VideoTerm and on Soft-70, a callback that moves the conio cursor
** must put it back (wherex, wherey, gotoxy).
**
** Under DOS 3.3, clock_gettime and time() return the software clock: the
** up-time until clock_settime sets it (for example, from IP65's SNTP
** client), then the time set plus the seconds counted since. It drifts
** slow by the time spent computing, so resynchronize now and then.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _A2TIMER_H
#define _A2TIMER_H

#define A2_TIMER_NONE   0xFF            /* a2_timer_start: no free slot */
#define A2_CLOCK_UNSET  0xFFFFFFFFUL    /* a2_clock_age: never set */

/* Milliseconds counted since the program started. */
unsigned long a2_millis (void);

/* Wait one tick (about 3.86 ms), running due callbacks. Keys are left
** alone. For a program's own idle loops. */
void a2_idle (void);

/* Call fn after ms milliseconds (rounded to ticks), once or, if periodic
** is nonzero, every ms milliseconds. Returns a handle, or A2_TIMER_NONE
** if all 4 slots are in use. A one-shot timer's slot is freed when it
** fires. */
unsigned char __fastcall__ a2_timer_start (unsigned ms, void (*fn) (void),
                                          unsigned char periodic);

/* Stop a timer and free its slot. */
void __fastcall__ a2_timer_stop (unsigned char handle);

/* Seconds since the software clock was last set with clock_settime, or
** A2_CLOCK_UNSET if it never was. A2_CLOCK_UNSET exceeds any threshold,
** so "if (a2_clock_age () > 3600) resync ();" also catches the unset
** case. */
unsigned long a2_clock_age (void);

#endif
