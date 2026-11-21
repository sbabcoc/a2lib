;
; Screen size variables
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
; on cc65's libsrc/apple2/_scrsize.s. 80 x 24, on the VideoTerm and in the
; model (s80.s) alike.
;

        .export         screensize

        .include        "s80.inc"
        .include        "display.inc"

screensize:
        ldx     #S80_COLS
        ldy     #S80_ROWS
        rts
