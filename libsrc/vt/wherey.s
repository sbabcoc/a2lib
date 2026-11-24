;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; unsigned char wherey (void);
;
;
; VideoTerm backend (a2lib-vt.lib): modified copy of libsrc/apple2/wherey.s
; from cc65; if the card is in use, returns its cursor row (DESIGN.md 3.4).

        .export         _wherey

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; _wherey: The cursor's row, from the top of the window: unsigned char wherey
; (void).
;
; Input:        none
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
