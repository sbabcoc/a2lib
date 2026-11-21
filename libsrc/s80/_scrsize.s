;
; Ullrich von Bassewitz, 26.10.2000
; Scott Babcock, 2026-11-14
;
; Screen size variables
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/_scrsize.s. 80 x 24, on the VideoTerm and in the model
; (s80.s) alike.
;

        .export         screensize

        .include        "s80.inc"
        .include        "display.inc"

screensize:
        ldx     #S80_COLS
        ldy     #S80_ROWS
        rts
