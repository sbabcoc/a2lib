;
; Scott Babcock, 2026-11-20
;
; The tick hook that the wait loops of cgetc() and kbhit() call each time they
; increment RNDH. It does nothing until the cooperative timer, linked when the
; program or a display library uses it, points it at its tick routine. In the
; timer library and each display library. For details, see section 6.3 of
; DESIGN.
;

        .include        "timer.inc"

        .data

;-----------------------------------------------------------------------------
; The tick hook: the wait loops of cgetc, kbhit and the display libraries'
; cgetc JSR here each time they increment RNDH. Returns at once until
; the timer's constructor points it at a2_tick.
;
; Changes:      Nothing, until the timer is linked; then what a2_tick
;               changes.

a2_tickhook:
        jmp     tickrts         ; Target set by the timer's constructor
a2_tickon:
        .byte   $00             ; Bit 7: the timer is in use

        .code

;-----------------------------------------------------------------------------
; a2_tickhook's target while the timer isn't in use.
;
; Changes:      Nothing.

tickrts:
        rts
