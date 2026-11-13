;
; 40-column window backend for the cc65 apple2 target (DESIGN.md 3.6)
;
; An 80 x 24 screen kept in memory (buf), of which columns win_left to
; win_left + 39 are shown on the 40-column text screen. It behaves like
; the VideoTerm backend: delayed wrap at column 80, '\r' to column 0, line
; feed in the same column, scrolling at the bottom. Panning follows the
; cursor by default, in steps of 20 columns, when a character is written
; or the cursor is about to be shown.
;
; buf holds screen codes XOR $A0, so that the zeroed BSS is a blank screen:
; crt0 clears BSS after the constructors run (DESIGN.md 6.1), so the buffer
; can't be initialized by a constructor. All state set by the constructor
; is in DATA for the same reason.
;
; Uses BASL and BAS2L ($28-$2B) as pointers, set on every use, and no other
; zero page: chline keeps counters in tmp1/tmp2 across cputdirect, and
; cputs its string in ptr1.
;
;   win_put:        write screen code A at the cursor and advance
;   win_putnoadv:   write screen code A at the cursor
;   win_cr:         column 0
;   win_lf:         next row, scrolling at the bottom
;   win_goto:       column X, row A (each ignored if out of range)
;   win_show:       if following, pan so the cursor's column is visible
;   win_clear:      clear, home, and show columns 0-39
;   win_cout:       the COUT hook: console output (bit 7 set)
;
; C interface (include/c40win.h): c40_pan, c40_follow, c40_left,
; c40_active. They do nothing (or report 0) while the VideoTerm is in use.
;
; Position gauge (DESIGN.md 6.3): after each pan, "[....====]" in inverse
; video in the top-right corner shows which 40 of the 80 columns are
; visible; a one-shot timer hides it after a second by restoring the corner
; from the buffer. Drawn only if a timer slot is free. The timer functions
; used here touch no zero page, since this runs inside cputc (cputs keeps
; ptr1, chline tmp1 and tmp2).
;

        .export         _c40_pan, _c40_follow, _c40_left, _c40_active
        .constructor    wininit, 6      ; After vt.s's (7): needs vt_active
        .destructor     windone
        .import         HOME, VTABZ
        .import         __dos_type

        .include        "apple2.inc"
        .include        "win.inc"
        .include        "vt.inc"
        .include        "timer.inc"

GAUGE_COL       = WIN_VIEW - 10 ; Gauge in columns 30-39 of row 0
GAUGE_TICKS     = MS_TICKS(1000)

        .segment        "ONCE"

wininit:
        bit     vt_active
        bmi     :+
        lda     CSWL
        sta     savecsw
        lda     CSWL+1
        sta     savecsw+1
        lda     DOS_CSW
        sta     savedos
        lda     DOS_CSW+1
        sta     savedos+1
        jsr     HOME            ; Clear the text screen
        lda     #<win_cout
        sta     CSWL
        lda     #>win_cout
        sta     CSWL+1
:       rts

        .code

windone:
        bit     vt_active
        bmi     done

        ; Remove the gauge, if shown
        bit     gslot
        bmi     :+
        jsr     gauge_hide
:

        ; Restore the output hooks, as vt.s does
        lda     savecsw
        sta     CSWL
        lda     savecsw+1
        sta     CSWL+1
        lda     __dos_type
        bne     :+
        lda     DOS_CSW
        cmp     #<win_cout
        bne     :+
        lda     DOS_CSW+1
        cmp     #>win_cout
        bne     :+
        lda     savedos
        sta     DOS_CSW
        lda     savedos+1
        sta     DOS_CSW+1

        ; Leave the monitor's cursor where the window's is, so BASIC
        ; continues below the program's output
:       jsr     win_cursorcol
        bcc     :+
        lda     #$00            ; Not visible: column 0
:       sta     CH
        lda     win_y
        sta     CV
        jmp     VTABZ
done:   rts

; ------------------------------------------------------------------------
; Output

win_put:
        pha
        jsr     wrap
        pla
        jsr     store
        inc     win_x           ; 80 = wrap pending
        rts

win_putnoadv:
        pha
        jsr     wrap
        pla
        ; Fall through

; store: put screen code A at the cursor, in the buffer and, if visible,
; on the screen.

store:  pha
        jsr     win_show
        jsr     win_bufptr
        ldy     win_x
        pla
        pha
        eor     #$A0
        sta     (BAS2L),y
        jsr     win_cursorcol
        bcs     :+
        pha                     ; Screen column
        lda     win_y
        jsr     win_scrptr      ; Changes Y
        pla
        tay
        pla                     ; Screen code
        sta     (BASL),y
        rts
:       pla
        rts

; wrap: a pending wrap (column 80) becomes CR + LF.

wrap:   lda     win_x
        cmp     #WIN_COLS
        bcc     :+
        jsr     win_cr
        jmp     win_lf
:       rts

win_cr: lda     #$00
        sta     win_x
        rts

win_lf: inc     win_y
        lda     win_y
        cmp     #WIN_ROWS
        bcc     :+
        dec     win_y
        jmp     scroll
:       rts

; scroll: move rows 1-23 up, clear row 23, redraw.

scroll: ldx     #$00
:       txa
        jsr     rowptrs         ; BASL = row X, BAS2L = row X + 1
        ldy     #WIN_COLS-1
:       lda     (BAS2L),y
        sta     (BASL),y
        dey
        bpl     :-
        inx
        cpx     #WIN_ROWS-1
        bne     :--
        lda     #WIN_ROWS-1
        jsr     setbuf          ; BAS2L = row 23
        lda     #$00            ; Blank
        ldy     #WIN_COLS-1
:       sta     (BAS2L),y
        dey
        bpl     :-
        jmp     redraw

; rowptrs: BASL = buffer row A, BAS2L = buffer row A + 1.

rowptrs:
        asl
        tay
        lda     bufrow,y
        sta     BASL
        lda     bufrow+1,y
        sta     BASL+1
        lda     bufrow+2,y
        sta     BAS2L
        lda     bufrow+3,y
        sta     BAS2L+1
        rts

; ------------------------------------------------------------------------
; Cursor and window

win_goto:
        cmp     #WIN_ROWS
        bcs     :+
        sta     win_y
:       cpx     #WIN_COLS
        bcs     :+
        stx     win_x
:       rts

; win_cursorcol: the cursor's screen column (A), carry clear if visible.
; A pending wrap counts as column 79.

win_cursorcol:
        lda     win_x
        cmp     #WIN_COLS
        bcc     :+
        lda     #WIN_COLS-1
:       sec
        sbc     win_left
        bcc     :+              ; Left of the window
        cmp     #WIN_VIEW       ; C set if right of it
        rts
:       sec
        rts

win_show:
        bit     win_follow
        bpl     done2
        lda     win_x
        cmp     #WIN_COLS
        bcc     :+
        lda     #WIN_COLS-1
:       cmp     win_left
        bcc     left            ; Left of the window
        sec
        sbc     win_left
        cmp     #WIN_VIEW
        bcc     done2           ; Visible

        ; Right of it: the smallest step that shows it (20 or 40)
        lda     win_x
        cmp     #WIN_COLS
        bcc     :+
        lda     #WIN_COLS-1
:       sec
        sbc     #WIN_VIEW-1     ; Columns needed beyond 0: 1-40
        cmp     #WIN_STEP+1
        lda     #WIN_STEP
        bcc     setleft
        lda     #WIN_STEP*2
        bne     setleft         ; Branch always

        ; Left of it: the step at or below its column (0 or 20)
left:   cmp     #WIN_STEP
        lda     #$00
        bcc     setleft
        lda     #WIN_STEP

setleft:
        sta     win_left
        jsr     redraw
        jmp     gauge_show
done2:  rts

; redraw: copy the window's 40 columns of each row to the screen.

redraw: ldx     #$00
:       txa
        jsr     win_scrptr      ; BASL = screen row
        txa
        jsr     setbuf          ; BAS2L = buffer row
        clc
        lda     BAS2L
        adc     win_left
        sta     BAS2L
        bcc     :+
        inc     BAS2L+1
:       ldy     #WIN_VIEW-1
:       lda     (BAS2L),y
        eor     #$A0
        sta     (BASL),y
        dey
        bpl     :-
        inx
        cpx     #WIN_ROWS
        bne     :---
        rts

win_clear:
        ldx     #$00
:       txa
        jsr     setbuf
        lda     #$00            ; Blank
        ldy     #WIN_COLS-1
:       sta     (BAS2L),y
        dey
        bpl     :-
        inx
        cpx     #WIN_ROWS
        bne     :--
        lda     #$00
        sta     win_x
        sta     win_y
        sta     win_left
        jmp     redraw

; win_bufptr / setbuf: BAS2L = the cursor's buffer row / buffer row A.

win_bufptr:
        lda     win_y
setbuf: asl
        tay
        lda     bufrow,y
        sta     BAS2L
        lda     bufrow+1,y
        sta     BAS2L+1
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
; COUT hook: console output, bit 7 set (stdio already applied
; uppercasemask). Preserves A, X and Y, as COUT's callers expect.

win_cout:
        pha
        txa
        pha
        tya
        pha
        tsx
        lda     $0103,x
        cmp     #$8D            ; Return: CR + LF
        bne     :+
        jsr     win_cr
        jsr     win_lf
        jmp     out
:       cmp     #$8A            ; Line feed
        bne     :+
        jsr     win_lf
        jmp     out
:       cmp     #$88            ; Backspace
        bne     :+
        jsr     back
        jmp     out
:       cmp     #$A0            ; Other controls: ignored
        bcc     out
        and     INVFLG          ; As the monitor's COUT does
        jsr     win_put
out:    pla
        tay
        pla
        tax
        pla
        rts

; back: one column left, as the VideoTerm firmware's backspace ($C96F):
; from a pending wrap (80) to 79; from column 0 to column 79 of the row
; above (staying on row 0 at the top).

back:   lda     win_x
        beq     :+
        dec     win_x
        rts
:       lda     #WIN_COLS-1
        sta     win_x
        lda     win_y
        beq     :+
        dec     win_y
:       rts

; ------------------------------------------------------------------------
; Position gauge

; gauge_show: (re)start the one-shot timer, then draw the gauge. Each of
; its 8 cells stands for 10 columns; the window covers 4, from cell
; win_left / 10 (rounded).

gauge_show:
        ldx     gslot
        bmi     :+
        jsr     a2_timer_restart
        jmp     draw
:       lda     #<GAUGE_TICKS
        sta     tmr_ticks
        lda     #>GAUGE_TICKS
        sta     tmr_ticks+1
        lda     #<gauge_hide
        sta     tmr_fn
        lda     #>gauge_hide
        sta     tmr_fn+1
        lda     #$00            ; One-shot
        sta     tmr_per
        jsr     a2_timer_arm
        cmp     #$FF
        beq     nogauge         ; No free slot: no gauge
        sta     gslot

draw:   lda     win_left        ; First covered cell: (win_left + 5) / 10
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
nogauge:
        rts

; gauge_hide: the timer's callback, also used at exit. Restores the
; gauge's corner from the buffer.

gauge_hide:
        lda     #$FF            ; The one-shot has freed its slot
        sta     gslot
        lda     #$00
        jsr     setbuf          ; BAS2L = buffer row 0
        clc
        lda     BAS2L
        adc     win_left
        sta     BAS2L
        bcc     :+
        inc     BAS2L+1
:       ldy     #GAUGE_COL
:       lda     (BAS2L),y
        eor     #$A0
        sta     $0400,y
        iny
        cpy     #WIN_VIEW
        bne     :-
        rts

; ------------------------------------------------------------------------
; C interface

_c40_pan:
        bit     vt_active
        bmi     :++
        cmp     #WIN_COLS-WIN_VIEW+1
        bcc     :+
        lda     #WIN_COLS-WIN_VIEW
:       sta     win_left
        lda     #$00            ; Stop following
        sta     win_follow
        jsr     redraw
        jmp     gauge_show
:       rts

_c40_follow:
        bit     vt_active
        bmi     :+
        lda     #$80
        sta     win_follow
        jmp     win_show
:       rts

_c40_left:
        lda     #$00
        bit     vt_active
        bmi     :+
        lda     win_left
:       ldx     #$00
        rts

_c40_active:
        lda     #$00
        bit     vt_active
        bmi     :+
        lda     #$01
:       ldx     #$00
        rts

        .rodata

; Text screen page 1 rows: $400 + (row & 7) * $80 + (row >> 3) * $28
scrrow: .repeat WIN_ROWS, i
        .word   $0400 + (i .mod 8) * $80 + (i / 8) * $28
        .endrepeat

bufrow: .repeat WIN_ROWS+1, i   ; One extra for rowptrs on row 22
        .word   buf + i * WIN_COLS
        .endrepeat

        .data

win_x:          .byte   $00
win_y:          .byte   $00
win_left:       .byte   $00
win_follow:     .byte   $80     ; Bit 7: follow the cursor
gslot:          .byte   $FF     ; Gauge's timer slot; bit 7: none
gcell:          .byte   $00
savecsw:        .word   $0000
savedos:        .word   $0000

        .bss

buf:            .res    WIN_COLS * WIN_ROWS
