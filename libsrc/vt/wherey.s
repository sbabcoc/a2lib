;
; Kevin Ruland
;
; unsigned char wherey (void);
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/wherey.s from cc65; if the card is in use, returns its cursor
; row.
; (DESIGN.md 3.4).

        .export         _wherey

        .include        "apple2.inc"
        .include        "vt.inc"

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
