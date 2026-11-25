;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; wherey() for the Soft-70 library: the VideoTerm's cursor row, or the 80 x 24
; model's. For details, see section 3.8 of DESIGN.
;

        .export         _wherey

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The cursor's row.
;
; Signature:    unsigned char wherey ()
; Overrides:    cc65's wherey()
; Output:       AX            unsigned char
;                                       the row
; Changes:      Flags. Y is unchanged.

_wherey:
        lda     s80_y
        bit     vt_active
        bpl     :+
        lda     VT_CVERT
:       ldx     #>$0000
        rts
