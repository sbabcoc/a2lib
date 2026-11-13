;
; Kevin Ruland
;
; unsigned char wherex (void);
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/wherex.s from cc65; if the card is in use, returns its cursor
; column (79 while a wrap is pending at column 80).
; (DESIGN.md 3.4).

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .export         _wherex

        .include        "apple2.inc"
        .include        "vt.inc"

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
