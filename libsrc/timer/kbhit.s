;
; Kevin Ruland
; Ullrich von Bassewitz, 2005-03-25
; Scott Babcock, 2026-11-13
;
; kbhit() for the timer library, as cc65's, except that while the timer is in
; use and no key is waiting, it waits for one tick (about 3.9 ms) or a key,
; with the same 15-cycle loop as cgetc(). Programs that poll kbhit() so
; advance the timer and run its callbacks. For details, see section 6.3 of
; DESIGN.
;

        .export _kbhit

        .include "apple2.inc"
        .include "timer.inc"

;-----------------------------------------------------------------------------
; Is a key waiting? While the timer is in use and none is, waits for a key or
; one tick first.
;
; Signature:    unsigned char kbhit ()
; Overrides:    cc65's kbhit()
; Input:        a2_tickon     byte      bit 7: the timer is in use
; Output:       X:A           unsigned char
;                                       1 if a key is waiting, else 0
; Changes:      Flags. When the timer is in use: Y, RNDL and RNDH, and what
;               a2_tick changes.

_kbhit:
        bit     KBD
        bmi     done            ; Key pending
        bit     a2_tickon
        bpl     done            ; Timer not in use

wait:   inc     RNDL
        bne     poll
        inc     RNDH
        jsr     a2_tickhook     ; One tick, then return
        jmp     done
poll:   lda     KBD
        bpl     wait

done:   lda     KBD             ; Reading KBD checks for keypress
        rol                     ; if high bit is set, key was pressed
        lda     #$00
        tax
        rol
        rts
