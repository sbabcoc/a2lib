;
; Ullrich von Bassewitz, 26.10.2000
;
; Screen size variables
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/_scrsize.s from cc65; if the card is in use, reports 80 x 24.
; (DESIGN.md 3.4).

        .export         screensize

        .include        "apple2.inc"
        .include        "vt.inc"

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
