;
; Zero-page check for the cooperative timer (DESIGN.md 6.3)
;
; unsigned char zp_check (void);
;
; Fills the C runtime's zero page (sreg through tmp4) with a pattern,
; calls kbhit until the C variable zp_fired becomes nonzero (set by a
; timer callback that uses that zero page itself), and returns 1 if the
; pattern survived, 0 if not. The test starts the timer before calling.
;

        .export         _zp_check
        .import         _kbhit, _zp_fired

        .include        "zeropage.inc"

ZPLEN = 18

_zp_check:
        ldx     #ZPLEN-1
:       txa
        eor     #$5A
        sta     sreg,x
        dex
        bpl     :-

:       jsr     _kbhit
        lda     _zp_fired
        beq     :-

        ldx     #ZPLEN-1
:       txa
        eor     #$5A
        cmp     sreg,x
        bne     bad
        dex
        bpl     :-
        lda     #$01
        ldx     #$00
        rts
bad:    lda     #$00
        tax
        rts
