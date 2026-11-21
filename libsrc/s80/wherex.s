;
; Kevin Ruland
; Scott Babcock, 2026-11-14
;
; unsigned char wherex (void);
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
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
