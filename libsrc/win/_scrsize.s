;
; Screen size variables
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/_scrsize.s. 80 x 24, on the VideoTerm and in the window
; alike.
;

        .export         screensize

        .include        "win.inc"

screensize:
        ldx     #WIN_COLS
        ldy     #WIN_ROWS
        rts
