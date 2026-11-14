;
; 40-column window display for the shared 80 x 24 model (DESIGN.md 3.6)
;
; Shows columns s80_left to s80_left + 39 of the model (libsrc/s80) on the
; 40-column text screen (page 1), which holds the screen codes themselves.
; Scrolling and clearing redraw the whole window from the buffer.
;
; Position gauge (DESIGN.md 6.3): "[....====]" in inverse video in the
; top-right corner shows which 40 of the 80 columns are visible; removing
; it restores the corner from the buffer.
;
; Uses BASL and BAS2L ($28-$2B) as pointers, set on every use, and no
; other zero page (s80.inc).
;

        .export         win_scrptr
        .import         HOME, VTABZ

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"

GAUGE_COL       = S80_VIEW - 10 ; Gauge in columns 30-39 of row 0

        .segment        "ONCE"

disp_init       := HOME         ; Clear the text screen

        .code

; disp_done: leave the monitor's cursor where the window's is, so BASIC
; continues below the program's output.

disp_done:
        jsr     s80_cursorcol
        bcc     :+
        lda     #$00            ; Not visible: column 0
:       sta     CH
        lda     s80_y
        sta     CV
        jmp     VTABZ

disp_cell:
        pha
        tya
        jsr     win_scrptr      ; BASL = text row
        txa
        tay
        pla
        sta     (BASL),y
        rts

; disp_redraw: copy the window's 40 columns of each row to the screen.

disp_scroll     := disp_redraw
disp_clear      := disp_redraw

disp_redraw:
        ldx     #$00
:       txa
        jsr     win_scrptr      ; BASL = screen row
        txa
        jsr     s80_setbuf      ; BAS2L = buffer row
        clc
        lda     BAS2L
        adc     s80_left
        sta     BAS2L
        bcc     :+
        inc     BAS2L+1
:       ldy     #S80_VIEW-1
:       lda     (BAS2L),y
        eor     #$A0
        sta     (BASL),y
        dey
        bpl     :-
        inx
        cpx     #S80_ROWS
        bne     :---
        rts

; win_scrptr: BASL = text screen row A (page 1).

win_scrptr:
        asl
        tay
        lda     scrrow,y
        sta     BASL
        lda     scrrow+1,y
        sta     BASL+1
        rts

; ------------------------------------------------------------------------
; Position gauge

; disp_gauge_draw: each of the gauge's 8 cells stands for 10 columns; the
; window covers 4, from cell s80_left / 10 (rounded).

disp_gauge_draw:
        lda     s80_left        ; First covered cell: (s80_left + 5) / 10
        clc
        adc     #5
        ldx     #$FF
:       inx
        sec
        sbc     #10
        bcs     :-
        stx     gcell
        lda     #'[' & $3F      ; Inverse
        sta     $0400 + GAUGE_COL
        lda     #']' & $3F
        sta     $0400 + GAUGE_COL + 9
        ldy     #$00
:       lda     #'.' & $3F
        cpy     gcell
        bcc     :+
        tya
        sec
        sbc     gcell
        cmp     #4
        lda     #'.' & $3F
        bcs     :+
        lda     #'=' & $3F
:       sta     $0400 + GAUGE_COL + 1,y
        iny
        cpy     #8
        bne     :--
        rts

; disp_gauge_erase: restore the gauge's corner from the buffer.

disp_gauge_erase:
        lda     #$00
        jsr     s80_setbuf      ; BAS2L = buffer row 0
        clc
        lda     BAS2L
        adc     s80_left
        sta     BAS2L
        bcc     :+
        inc     BAS2L+1
:       ldy     #GAUGE_COL
:       lda     (BAS2L),y
        eor     #$A0
        sta     $0400,y
        iny
        cpy     #S80_VIEW
        bne     :-
        rts

        .rodata

; Text screen page 1 rows: $400 + (row & 7) * $80 + (row >> 3) * $28
scrrow: .repeat S80_ROWS, i
        .word   $0400 + (i .mod 8) * $80 + (i / 8) * $28
        .endrepeat

        .bss

gcell:          .res    1
