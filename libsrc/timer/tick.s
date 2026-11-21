;
; Scott Babcock, 2026-11-20
;
; Tick hook for the cc65 apple2 target (DESIGN.md 6.3)
;
; The wait loops of a2lib-timer.lib's cgetc and kbhit, and of the display
; libraries' cgetc, JSR a2_tickhook each time they increment RNDH. It does
; nothing until the timer module (timer.s), linked when the program or a
; display library uses it, points it at a2_tick and sets a2_tickon. In
; a2lib-timer.lib and in each display library.
;

        .include        "timer.inc"

        .data

a2_tickhook:
        jmp     tickrts         ; Target set by timer.s's constructor
a2_tickon:
        .byte   $00             ; Bit 7: the timer is in use

        .code

tickrts:
        rts
