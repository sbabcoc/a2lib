;
; Scott Babcock, 2026-11-20
;
; int __fastcall__ clock_gettime (clockid_t clk_id, struct timespec *tp);
;
; Link-time guard (DESIGN.md 4.2): DOS 3.3 has no clock; the software clock
; is in a2lib-timer.lib (DESIGN.md 6.3). Replaces cc65's ProDOS module of
; the same name in a2lib-dos33.lib, so a program that calls clock_gettime
; (or time) without the timer fails to link instead, naming the symbol
; below. Linked with a2lib-timer.o and a2lib-timer.lib ahead of
; a2lib-dos33.lib, the timer's clock_gettime is linked instead.
;

        .export         _clock_gettime
        .import         clock_gettime_needs_a2lib_timer

_clock_gettime  := clock_gettime_needs_a2lib_timer
