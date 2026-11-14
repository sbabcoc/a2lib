;
; unsigned char wherex (void);
;
; 80 x 24 backends (apple2-dos33-vtwin.lib, apple2-dos33-vts70.lib), based
; on cc65's libsrc/apple2/wherex.s. The cursor's column, 0-79 (79 while a
; wrap is pending).
;

        .export         _wherex

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

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
