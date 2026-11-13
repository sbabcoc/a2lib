;
; Kevin Ruland
; Ullrich von Bassewitz, 2005-03-25
;
; unsigned char kbhit (void);
;
; Cooperative timer (DESIGN.md 6.3): modified copy of libsrc/apple2/kbhit.s
; from cc65. While the timer is in use and no key is pending, waits for
; one tick (about 3.9 ms) or a key, with the same 15-cycle loop as cgetc,
; so programs that poll kbhit advance the timer and run its callbacks.
; Otherwise unchanged.
;

        .export _kbhit

        .include "apple2.inc"
        .include "timer.inc"

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
