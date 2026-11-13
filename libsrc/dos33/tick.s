;
; Tick hook for the cc65 apple2 target (DESIGN.md 6.3)
;
; The library's wait loops (cgetc, kbhit) JSR a2_tickhook each time they
; increment RNDH. It does nothing until the timer module (timer.s), which
; is linked only if a program uses it, points it at a2_tick and sets
; a2_tickon. Programs that don't use the timer pay these few bytes.
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
