;
; Ullrich von Bassewitz, 26.10.2000
; Scott Babcock, 2026-11-14
;
; The screen's size for the Soft-70 library: 80 x 24, on the VideoTerm and in
; the model alike. For details, see section 3.8 of DESIGN.
;

        .export         screensize

        .include        "s80.inc"
        .include        "display.inc"

;-----------------------------------------------------------------------------
; The screen's size, for cc65's screensize(): 80 x 24, on the VideoTerm and in
; the model alike.
;
; Overrides:    cc65's screensize
; Output:       X             byte      80
;               Y             byte      24
; Changes:      Flags. A is unchanged.

screensize:
        ldx     #S80_COLS
        ldy     #S80_ROWS
        rts
