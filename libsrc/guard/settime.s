;
; Scott Babcock, 2026-11-20
;
; A link-time guard for clock_settime(), in place of cc65's ProDOS version.
; DOS 3.3 has no clock; the software clock is in the timer library. A program
; that calls clock_settime() without the timer library fails to link instead,
; naming the symbol below. With the timer's selector and library ahead of the
; DOS 3.3 library, the timer's clock_settime() is linked instead. For details,
; see sections 4.2 and 6.3 of DESIGN.
;

        .export         _clock_settime
        .import         clock_settime_needs_a2lib_timer

_clock_settime  := clock_settime_needs_a2lib_timer
