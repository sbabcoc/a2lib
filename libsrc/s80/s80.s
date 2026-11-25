;
; Scott Babcock, 2026-11-14
;
; The 80 x 24 screen model that Soft-70 shows part of: a screen in memory, of
; which columns s80_left to s80_left + S80_VIEW - 1 are shown. It behaves like
; the VideoTerm: a delayed wrap at column 80, '\r' to column 0, a line feed in
; the same column, scrolling at the bottom. The view follows the cursor by
; default, in steps of S80_STEP columns, when a character is written or the
; cursor is about to be shown. The C interface lets a program pan the view
; itself.
;
; After each pan, a position gauge shows which columns are visible, and a
; one-shot timer removes it after a second, if a timer slot is free.
;
; The buffer holds screen codes XOR #$A0, so that zeroed memory is a blank
; screen. The startup code clears BSS after the constructors run, so all the
; state the constructor sets is in DATA. The model uses BASL and BAS2L as
; pointers, set on every use, and no other zero page: it runs inside cputc(),
; and cputs() keeps its string in ptr1, chline() its counters in tmp1 and
; tmp2. For details, see sections 3.8 and 6.3 of DESIGN.
;

        .constructor    s80init, 6      ; After the VideoTerm's (7)
        .destructor     s80done

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"
        .include        "timer.inc"
        .include        "machine.inc"

        .export         .ident(.concat(S80_API, "pan"))
        .export         .ident(.concat(S80_API, "follow"))
        .export         .ident(.concat(S80_API, "left"))
        .export         .ident(.concat(S80_API, "active"))

GAUGE_TICKS     = MS_TICKS(1000)

        .segment        "ONCE"

;-----------------------------------------------------------------------------
; The module constructor, unless the VideoTerm is in use: start the display,
; clear the buffer, write the text marker, and hook console output to
; s80_cout.
;
; Input:        vt_active     byte      bit 7: the VideoTerm is in use
; Output:       s80_marker    byte[16]  the text marker
;               s80_buf       byte[]    blank
; Changes:      A, X and Y; BAS2L; the output hooks (a2_hookout); what
;               disp_init changes.

s80init:
        bit     vt_active
        bmi     initdone
        jsr     a2_savehooks
        jsr     disp_init       ; Clears the display

        ; The buffer is in LOWBSS, which crt0 doesn't clear. (One in BSS
        ; couldn't be written here: apple2.cfg starts BSS where ONCE starts,
        ; so clearing it would overwrite this code.)
        jsr     clearbuf

        ; The text marker, for emulators and other tools that copy the
        ; screen's text
        ldx     #MARKLEN-1
:       lda     marktpl,x
        sta     s80_marker,x
        dex
        bpl     :-

        ; Console output into the model
        lda     #<s80_cout
        ldx     #>s80_cout
        jmp     a2_hookout
initdone:
        rts

; The text marker: written before the buffer at startup, its first byte
; cleared at exit. For details, see section 3.9 of DESIGN.
marktpl:
        .byte   "A2SCR80"       ; Signature
        .byte   1               ; Version
        .byte   S80_COLS, S80_ROWS, S80_VIEW
        .byte   S80_TEXTENC     ; Encoding of the buffer's bytes
        .addr   s80_left        ; Leftmost visible column (a byte)
        .addr   s80_buf         ; The buffer: rows of S80_COLS bytes
MARKLEN = * - marktpl
        .assert MARKLEN = 16, error, "text marker is 16 bytes"

        .code

;-----------------------------------------------------------------------------
; The module destructor, unless the VideoTerm is in use: clear the text
; marker's first byte, remove the gauge, put back the output hooks, and stop
; the display.
;
; Changes:      A, X and Y; the output hooks; what disp_done changes.

s80done:
        bit     vt_active
        bmi     done

        lda     #$00            ; No text marker after exit
        sta     s80_marker

        ; Remove the gauge, if shown
        bit     gslot
        bmi     :+
        jsr     gauge_hide
:

        ; Restore the output hooks
        jsr     a2_unhookout
        jmp     disp_done
done:   rts

; ------------------------------------------------------------------------
; Output

;-----------------------------------------------------------------------------
; Write a screen code at the cursor and advance; column 80 is a pending wrap,
; which the next character turns into CR and LF.
;
; Input:        A             byte      the screen code
; Output:       s80_x         byte      one higher
; Changes:      A, X, Y and flags; the buffer and the display; BASL and BAS2L.

s80_put:
        pha
        jsr     wrap
        pla
        jsr     store
        inc     s80_x           ; 80 = wrap pending
        rts

;-----------------------------------------------------------------------------
; Write a screen code at the cursor, without advancing. Falls into store.
;
; Input:        A             byte      the screen code
; Changes:      A, X, Y and flags; the buffer and the display; BASL and BAS2L.

s80_putnoadv:
        pha
        jsr     wrap
        pla
        ; Fall through


;-----------------------------------------------------------------------------
; Put a screen code at the cursor: in the buffer and, if its column is
; visible, on the display. Pans first if following (s80_show).
;
; Input:        A             byte      the screen code
;               s80_x, s80_y  byte      the cursor
; Changes:      A, X, Y and flags; the buffer and the display; BASL and BAS2L.

store:  pha
        jsr     s80_show
        jsr     s80_bufptr
        ldy     s80_x
        pla
        pha
        eor     #S80_BUF_XOR
        sta     (BAS2L),y
        jsr     s80_cursorcol
        tax                     ; Screen column
        pla                     ; Screen code
        bcs     :+              ; Not visible
        ldy     s80_y
        jmp     disp_cell
:       rts

;-----------------------------------------------------------------------------
; Turn a pending wrap (column 80) into CR and LF.
;
; Input:        s80_x         byte      the cursor's column
; Changes:      A, X, Y and flags; s80_x and s80_y; on a scroll, the buffer,
;               the display, BASL and BAS2L.

wrap:   lda     s80_x
        cmp     #S80_COLS
        bcc     :+
        jsr     s80_cr
        jmp     s80_lf
:       rts

;-----------------------------------------------------------------------------
; Move the cursor to column 0.
;
; Output:       s80_x         byte      0
; Changes:      A and flags. X and Y are unchanged.

s80_cr: lda     #$00
        sta     s80_x
        rts

;-----------------------------------------------------------------------------
; Move the cursor down a row, in the same column, scrolling at the bottom.
;
; Output:       s80_y         byte      one higher, at most 23
; Changes:      A and flags. On a scroll: X and Y, the buffer, the display,
;               BASL and BAS2L.

s80_lf: inc     s80_y
        lda     s80_y
        cmp     #S80_ROWS
        bcc     :+
        dec     s80_y
        jmp     scroll
:       rts

;-----------------------------------------------------------------------------
; Move the buffer's rows 1-23 up a row, blank row 23, and update the display
; (disp_scroll).
;
; Changes:      A, X, Y and flags; the buffer and the display; BASL and BAS2L.

scroll: ldx     #$00
@row:   txa
        jsr     rowptrs         ; BASL = row X, BAS2L = row X + 1
        ldy     #S80_COLS-1
@col:   lda     (BAS2L),y
        sta     (BASL),y
        dey
        bpl     @col
        inx
        cpx     #S80_ROWS-1
        bne     @row
        lda     #S80_ROWS-1
        jsr     s80_setbuf      ; BAS2L = row 23
        lda     #$00            ; Blank
        ldy     #S80_COLS-1
:       sta     (BAS2L),y
        dey
        bpl     :-
        jmp     disp_scroll

;-----------------------------------------------------------------------------
; Point BASL at a buffer row and BAS2L at the next.
;
; Input:        A             byte      the row, 0-22
; Output:       BASL          byte*     row A
;               BAS2L         byte*     row A + 1
; Changes:      A, Y and flags. X is unchanged.

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

;-----------------------------------------------------------------------------
; Move the cursor, ignoring each coordinate that is out of range.
;
; Input:        X             byte      the column, 0-79
;               A             byte      the row, 0-23
; Output:       s80_x, s80_y  byte      the cursor
; Changes:      Flags. A, X and Y are unchanged.

s80_goto:
        cmp     #S80_ROWS
        bcs     :+
        sta     s80_y
:       cpx     #S80_COLS
        bcs     :+
        stx     s80_x
:       rts

;-----------------------------------------------------------------------------
; The cursor's screen column. A pending wrap counts as column 79.
;
; Input:        s80_x         byte      the cursor's column
;               s80_left      byte      the leftmost visible column
; Output:       A             byte      s80_x - s80_left
;               C             flag      clear: visible; set: not
; Changes:      Flags. X and Y are unchanged.

s80_cursorcol:
        lda     s80_x
        cmp     #S80_COLS
        bcc     :+
        lda     #S80_COLS-1
:       sec
        sbc     s80_left
        bcc     :+              ; Left of the window
        cmp     #S80_VIEW       ; C set if right of it
        rts
:       sec
        rts

;-----------------------------------------------------------------------------
; If following, pan by the smallest number of S80_STEP steps that shows the
; cursor's column, redraw, and show the gauge.
;
; Input:        s80_follow    byte      bit 7: follow the cursor
;               s80_x         byte      the cursor's column
; Output:       s80_left      byte      a multiple of S80_STEP
; Changes:      A, X and Y; need; on a pan, the display and the gauge's timer.

s80_show:
        bit     s80_follow
        bpl     done2
        lda     s80_x
        cmp     #S80_COLS
        bcc     :+
        lda     #S80_COLS-1
:       cmp     s80_left
        bcc     left            ; Left of the window
        sec
        sbc     s80_left
        cmp     #S80_VIEW
        bcc     done2           ; Visible

        ; Right of it: the smallest step that shows it
        lda     s80_x
        cmp     #S80_COLS
        bcc     :+
        lda     #S80_COLS-1
:       sec
        sbc     #S80_VIEW-1     ; Columns needed beyond 0
        sta     need
        lda     #$00
:       clc
        adc     #S80_STEP
        cmp     need
        bcc     :-
        bcs     setleft         ; Branch always

        ; Left of it: the step at or below its column
left:   sta     need
        lda     #$00
:       tax                     ; A step at or below it
        clc
        adc     #S80_STEP
        cmp     need
        bcc     :-              ; The next one is too
        beq     :-
        txa

setleft:
        sta     s80_left
        jsr     disp_redraw
        jmp     gauge_show
done2:  rts

;-----------------------------------------------------------------------------
; Blank the buffer, home the cursor, and show columns 0 to S80_VIEW - 1.
;
; Output:       s80_x         byte      0
;               s80_y         byte      0
;               s80_left      byte      0
; Changes:      A, X, Y and flags; the buffer and the display; BAS2L.

s80_clear:
        jsr     clearbuf
        lda     #$00
        sta     s80_x
        sta     s80_y
        sta     s80_left
        jmp     disp_clear

;-----------------------------------------------------------------------------
; Blank the buffer.
;
; Output:       s80_buf       byte[]    blank (zero)
; Changes:      A, X, Y and flags; BAS2L.

clearbuf:
        ldx     #$00
@row:   txa
        jsr     s80_setbuf
        lda     #$00            ; Blank
        ldy     #S80_COLS-1
@col:   sta     (BAS2L),y
        dey
        bpl     @col
        inx
        cpx     #S80_ROWS
        bne     @row
        rts

;-----------------------------------------------------------------------------
; Point BAS2L at the cursor's buffer row. Falls into s80_setbuf.
;
; Input:        s80_y         byte      the cursor's row
; Output:       BAS2L         byte*     the row
; Changes:      A, Y and flags. X is unchanged.

s80_bufptr:
        lda     s80_y

;-----------------------------------------------------------------------------
; Point BAS2L at a buffer row.
;
; Input:        A             byte      the row, 0-23
; Output:       BAS2L         byte*     the row
; Changes:      A, Y and flags. X is unchanged.

s80_setbuf:
        asl
        tay
        lda     bufrow,y
        sta     BAS2L
        lda     bufrow+1,y
        sta     BAS2L+1
        rts

; ------------------------------------------------------------------------
; Console output

;-----------------------------------------------------------------------------
; The COUT hook: console output into the model. Return is CR and LF, and line
; feed and backspace work as on the VideoTerm; other controls are ignored. The
; others are stored as the monitor's COUT stores them (S80_ATTR), stdio having
; already applied uppercasemask.
;
; Input:        A             char      the character, bit 7 set
; Changes:      Flags; the buffer and the display; BASL and BAS2L. A, X and Y
;               are unchanged, as COUT's callers expect.

s80_cout:
        pha
        txa
        pha
        tya
        pha
        tsx
        lda     $0103,x
        cmp     #HI_CR          ; Return: CR + LF
        bne     :+
        jsr     s80_cr
        jsr     s80_lf
        jmp     out
:       cmp     #HI_LF
        bne     :+
        jsr     s80_lf
        jmp     out
:       cmp     #HI_BS
        bne     :+
        jsr     back
        jmp     out
:       cmp     #HI_SPACE       ; Other controls: ignored
        bcc     out
        S80_ATTR                ; As the monitor's COUT does
        jsr     s80_put
out:    pla
        tay
        pla
        tax
        pla
        rts

;-----------------------------------------------------------------------------
; Move the cursor one column left, as the VideoTerm firmware's backspace
; ($C96F): from a pending wrap (80) to 79, and from column 0 to column 79 of
; the row above, staying on row 0 at the top.
;
; Changes:      A and flags; s80_x and s80_y. X and Y are unchanged.

back:   lda     s80_x
        beq     :+
        dec     s80_x
        rts
:       lda     #S80_COLS-1
        sta     s80_x
        lda     s80_y
        beq     :+
        dec     s80_y
:       rts

; ------------------------------------------------------------------------
; Position gauge

;-----------------------------------------------------------------------------
; Restart the gauge's one-shot timer, or arm one if none is counting, then
; have the display show the gauge. No gauge if no timer slot is free.
;
; Input:        gslot         byte      the gauge's timer slot; bit 7: none
; Output:       gslot         byte      the slot, if one was armed
; Changes:      A, X, Y and flags; the timer's slot, tmr_ticks, tmr_fn and
;               tmr_per; the display. Leaves the C zero page alone: this runs
;               inside cputc.

gauge_show:
        ldx     gslot
        bmi     :+
        jsr     a2_timer_restart
        jmp     disp_gauge_draw
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
        beq     :+              ; No free slot: no gauge
        sta     gslot
        jmp     disp_gauge_draw
:       rts

;-----------------------------------------------------------------------------
; The gauge's timer callback, also used at exit: forget the slot (a one-shot
; frees its own) and have the display remove the gauge.
;
; Output:       gslot         byte      $FF
; Changes:      A, X, Y and flags; the display.

gauge_hide:
        lda     #$FF            ; The one-shot has freed its slot
        sta     gslot
        jmp     disp_gauge_erase

; ------------------------------------------------------------------------
; C interface

;-----------------------------------------------------------------------------
; Show the columns from left on, and stop following the cursor. Named S80_API
; + "pan". Does nothing while the VideoTerm is in use.
;
; Signature:    void __fastcall__ s70_pan (unsigned char left)
; Input:        A             unsigned char
;                                       leftmost column, at most 80 - S80_VIEW
; Output:       s80_left      byte      left
;               s80_follow    byte      0
; Changes:      A, X, Y and flags; the display and the gauge.

.ident(.concat(S80_API, "pan")):
        bit     vt_active
        bmi     @done
        cmp     #S80_COLS-S80_VIEW+1
        bcc     @set
        lda     #S80_COLS-S80_VIEW
@set:   sta     s80_left
        lda     #$00            ; Stop following
        sta     s80_follow
        jsr     disp_redraw
        jmp     gauge_show
@done:  rts

;-----------------------------------------------------------------------------
; Follow the cursor again, panning now if needed. Named S80_API + "follow".
; Does nothing while the VideoTerm is in use.
;
; Signature:    void s70_follow ()
; Output:       s80_follow    byte      $80
; Changes:      As s80_show.

.ident(.concat(S80_API, "follow")):
        bit     vt_active
        bmi     :+
        lda     #$80
        sta     s80_follow
        jmp     s80_show
:       rts

;-----------------------------------------------------------------------------
; The leftmost visible column. Named S80_API + "left".
;
; Signature:    unsigned char s70_left ()
; Output:       X:A           unsigned char
;                                       s80_left, or 0 while the VideoTerm is
;                                       in use
; Changes:      Flags. Y is unchanged.

.ident(.concat(S80_API, "left")):
        lda     #$00
        bit     vt_active
        bmi     :+
        lda     s80_left
:       ldx     #$00
        rts

;-----------------------------------------------------------------------------
; Is the 80 x 24 model in use? Named S80_API + "active".
;
; Signature:    unsigned char s70_active ()
; Output:       X:A           unsigned char
;                                       1, or 0 while the VideoTerm is in use
; Changes:      Flags. Y is unchanged.

.ident(.concat(S80_API, "active")):
        lda     #$00
        bit     vt_active
        bmi     :+
        lda     #$01
:       ldx     #$00
        rts

        .rodata

bufrow: .repeat S80_ROWS+1, i   ; One extra for rowptrs on row 22
        .word   s80_buf + i * S80_COLS
        .endrepeat

        .data

s80_x:          .byte   $00     ; The cursor's column; 80: wrap pending
s80_y:          .byte   $00     ; The cursor's row
s80_left:       .byte   $00     ; The leftmost visible column
s80_follow:     .byte   $80     ; Bit 7: follow the cursor
gslot:          .byte   $FF     ; Gauge's timer slot; bit 7: none
need:           .byte   $00     ; s80_show: the column to reach

        .segment        "LOWBSS"

s80_marker:     .res    MARKLEN         ; Directly before the buffer
s80_buf:        .res    S80_COLS * S80_ROWS
