;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; wherey() for the VideoTerm library: on the card, its cursor's row. For
; details, see section 3.4 of DESIGN.
;

        .export         _wherey

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The cursor's row, from the top of the window.
;
; Signature:    unsigned char wherey ()
; Overrides:    cc65's wherey()
; Output:       AX            unsigned char
;                                       the row
; Changes:      Flags. Y is unchanged.

_wherey:
        bit     vt_active
        bmi     vt
        lda     CV
        sec
        sbc     WNDTOP
        ldx     #>$0000
        rts

vt:     lda     VT_CVERT
        ldx     #>$0000
        rts
