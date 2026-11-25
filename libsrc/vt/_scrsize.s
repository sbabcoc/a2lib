;
; Ullrich von Bassewitz, 26.10.2000
; Scott Babcock, 2026-11-12
;
; The screen's size for the VideoTerm library: 80 x 24 while the card is in
; use, else the stock screen's. For details, see section 3.4 of DESIGN.
;

        .export         screensize

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The screen's size, for cc65's screensize(): 80 x 24 on the card, else the
; window's.
;
; Overrides:    cc65's screensize
; Output:       X             byte      the width in columns
;               Y             byte      the height in rows
; Changes:      A and flags.

screensize:
        bit     vt_active
        bmi     vt
        ldx     WNDWDTH
        lda     WNDBTM
        sec
        sbc     WNDTOP
        tay
        rts

vt:     ldx     #VT_COLS
        ldy     #VT_ROWS
        rts
