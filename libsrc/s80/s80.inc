;
; The interface between the 80 x 24 model and the display that shows part of
; it, Soft-70's. The display's own include file defines:
;
;   S80_VIEW        visible columns (70)
;   S80_STEP        panning step: the display shows columns left to
;                   left + S80_VIEW - 1, left a multiple of S80_STEP
;   S80_API         prefix of the C interface ("_s70_")
;   S80_ATTR        macro: apply INVFLG to the screen code in A
;   S80_PEEK        macro: the character for the screen code in A
;
; and the display's routines, which the model calls. For details, see section
; 3.8 of DESIGN.
;

S80_COLS        = 80
S80_ROWS        = 24

BAS2L           := $2A          ; Monitor zero page, used as a second pointer

        ; The model
        .global         s80_x, s80_y, s80_left, s80_follow
        .global         s80_put, s80_putnoadv, s80_cr, s80_lf
        .global         s80_goto, s80_show, s80_clear, s80_cout
        .global         s80_bufptr, s80_setbuf, s80_cursorcol
        .global         s80_buf         ; 80 x 24, screen codes XOR S80_BUF_XOR

S80_BUF_XOR     = $A0           ; s80_buf holds screen code XOR this, so a
                                ; blank (screen code $A0) is stored as $00

        ; The display. Each may use A, X, Y, BASL and BAS2L, and no other
        ; zero page (cputs keeps ptr1, chline tmp1 and tmp2).
        ;   disp_init:          constructor, before the model clears the
        ;                       screen (ONCE)
        ;   disp_done:          destructor
        ;   disp_cell:          show screen code A at screen column X, row Y
        ;   disp_redraw:        show the window's columns of every row
        ;   disp_scroll:        the buffer has scrolled up one row
        ;   disp_clear:         the buffer has been cleared, s80_left is 0
        ;   disp_gauge_draw:    show the position gauge for s80_left (shown
        ;                       or not)
        ;   disp_gauge_erase:   remove it (a timer callback)
        .global         disp_init, disp_done, disp_cell, disp_redraw
        .global         disp_scroll, disp_clear
        .global         disp_gauge_draw, disp_gauge_erase
