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
        .global         s80_x            ; Cursor column; 80: wrap pending
        .global         s80_y            ; The cursor's row
        .global         s80_left         ; The leftmost visible column
        .global         s80_follow       ; Bit 7: follow the cursor
        .global         s80_put          ; Write a screen code and advance
        .global         s80_putnoadv     ; Write a screen code
        .global         s80_cr           ; Column 0
        .global         s80_lf           ; Down a row, scrolling
        .global         s80_goto         ; Move the cursor
        .global         s80_show         ; Pan to the cursor if following
        .global         s80_clear        ; Clear and home
        .global         s80_cout         ; The COUT hook
        .global         s80_bufptr       ; BAS2L: the cursor's row
        .global         s80_setbuf       ; BAS2L: a row
        .global         s80_cursorcol    ; The cursor's screen column
        .global         s80_buf          ; Screen codes XOR S80_BUF_XOR

S80_BUF_XOR     = $A0           ; s80_buf holds screen code XOR this, so a
                                ; blank (screen code $A0) is stored as $00

; The display's routines, which the model calls. Each may use A, X, Y, BASL
; and BAS2L, and no other zero page: cputs() keeps ptr1, chline() tmp1 and
; tmp2.
        .global         disp_init        ; Start, before the buffer is cleared
        .global         disp_done        ; Stop
        .global         disp_cell        ; Show a screen code in a cell
        .global         disp_redraw      ; Show the window's columns
        .global         disp_scroll      ; The buffer has scrolled a row
        .global         disp_clear       ; The buffer has been cleared
        .global         disp_gauge_draw  ; Show the position gauge
        .global         disp_gauge_erase ; Remove it (a timer callback)
