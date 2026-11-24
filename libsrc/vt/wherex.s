;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; unsigned char wherex (void);
;
;
; VideoTerm backend (a2lib-vt.lib): modified copy of libsrc/apple2/wherex.s
; from cc65; if the card is in use, returns its cursor column (79 while a
; wrap is pending at column 80) (DESIGN.md 3.4).

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .export         _wherex

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; _wherex: The cursor's column: unsigned char wherex (void). On the card, 79
; while a wrap is pending at column 80.
;
; Input:        none
; Output:       AX            unsigned char
;                                       the column
; Changes:      Flags. Y is unchanged.

_wherex:
        bit     vt_active
        bmi     vt
        lda     CH
        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     :+
        .endif
        bit     RD80VID         ; In 80 column mode?
        bpl     :+
        lda     OURCH

:       ldx     #>$0000
        rts

vt:     lda     VT_CHORZ
        cmp     #VT_COLS
        bcc     :+
        lda     #VT_COLS-1
:       ldx     #>$0000
        rts
