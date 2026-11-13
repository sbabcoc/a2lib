;
; 40-column window backend for the cc65 apple2 target (DESIGN.md 3.6)
;
; An 80 x 24 screen kept in memory, of which a 40-column window is shown
; on the text screen. Used when no VideoTerm is found.
;

WIN_COLS        = 80
WIN_ROWS        = 24
WIN_VIEW        = 40            ; Visible columns
WIN_STEP        = 20            ; Panning step

BAS2L           := $2A          ; Monitor zero page, used as a second pointer

        .global         win_x, win_y, win_left, win_follow
        .global         win_put, win_putnoadv, win_cr, win_lf
        .global         win_goto, win_show, win_clear, win_cout
        .global         win_bufptr, win_scrptr, win_cursorcol
