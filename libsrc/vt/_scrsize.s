;
; Ullrich von Bassewitz, 26.10.2000
; Scott Babcock, 2026-11-12
;
; Screen size variables
;
;
; VideoTerm backend (a2lib-vt.lib; DESIGN.md 3.4): modified copy of
; libsrc/apple2/_scrsize.s from cc65; if the card is in use, reports 80 x 24.

        .export         screensize

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; screensize: The screen's size, for cc65's screensize(): 80 x 24 on the card,
; else the window's.
;
; Input:        none
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
