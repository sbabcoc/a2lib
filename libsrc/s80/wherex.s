;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; wherex() for the Soft-70 library: the VideoTerm's cursor column, or the 80 x
; 24 model's. For details, see section 3.8 of DESIGN.
;

        .export         _wherex

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The cursor's column, 0-79 (79 while a wrap is pending).
;
; Signature:    unsigned char wherex ()
; Overrides:    cc65's wherex()
; Output:       AX            unsigned char
;                                       the column
; Changes:      Flags. Y is unchanged.

_wherex:
        lda     s80_x
        bit     vt_active
        bpl     :+
        lda     VT_CHORZ
:       cmp     #S80_COLS
        bcc     :+
        lda     #S80_COLS-1
:       ldx     #>$0000
        rts
