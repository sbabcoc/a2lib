;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; wherex() for the VideoTerm library: on the card, its cursor's column. For
; details, see section 3.4 of DESIGN.
;

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .export         _wherex

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The cursor's column. On the card, 79 while a wrap is pending at column 80.
;
; Signature:    unsigned char wherex ()
; Overrides:    cc65's wherex()
; Output:       X:A           unsigned char
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
