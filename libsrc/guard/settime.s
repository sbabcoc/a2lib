;
; Scott Babcock, 2026-11-20
;
; int __fastcall__ clock_settime (clockid_t clk_id, const struct timespec *tp);
;
; Link-time guard (DESIGN.md 4.2): DOS 3.3 has no clock; the software clock
; is in a2lib-timer.lib (DESIGN.md 6.3). Replaces cc65's ProDOS module of
; the same name in a2lib-dos33.lib, so a program that calls clock_settime
; without the timer fails to link instead, naming the symbol below.
;

        .export         _clock_settime
        .import         clock_settime_needs_a2lib_timer

_clock_settime  := clock_settime_needs_a2lib_timer
