;
; Shared 80 x 24 screen model (DESIGN.md 3.1, 3.6, 3.8; s80.inc)
;
; An 80 x 24 screen kept in memory (s80_buf), of which columns s80_left to
; s80_left + S80_VIEW - 1 are shown by the display (display.inc). It
; behaves like the VideoTerm backend: delayed wrap at column 80, '\r' to
; column 0, line feed in the same column, scrolling at the bottom. Panning
; follows the cursor by default, in steps of S80_STEP columns, when a
; character is written or the cursor is about to be shown.
;
; s80_buf holds screen codes XOR $A0, so that zeroed memory is a blank
; screen. crt0 clears BSS after the constructors run (DESIGN.md 6.1), so
; all state set by the constructor is in DATA. A buffer in BSS is left to
; crt0: BSS starts where the constructors' code (ONCE) does, so writing it
; from a constructor would overwrite that code. The constructor clears a
; buffer outside BSS (Soft-70's, in LOWBSS) itself.
;
; Uses BASL and BAS2L ($28-$2B) as pointers, set on every use, and no other
; zero page: chline keeps counters in tmp1/tmp2 across cputdirect, and
; cputs its string in ptr1.
;
;   s80_put:        write screen code A at the cursor and advance
;   s80_putnoadv:   write screen code A at the cursor
;   s80_cr:         column 0
;   s80_lf:         next row, scrolling at the bottom
;   s80_goto:       column X, row A (each ignored if out of range)
;   s80_show:       if following, pan so the cursor's column is visible
;   s80_clear:      clear, home, and show columns 0 to S80_VIEW - 1
;   s80_cout:       the COUT hook: console output (bit 7 set)
;
; C interface, named S80_API + pan, follow, left, active (include/c40win.h,
; include/soft70.h). They do nothing (or report 0) while the VideoTerm is
; in use.
;
; Position gauge (DESIGN.md 6.3): after each pan, the display shows which
; columns are visible; a one-shot timer removes it after a second. Shown
; only if a timer slot is free. The timer functions used here touch no
; zero page, since this runs inside cputc (cputs keeps ptr1, chline tmp1
; and tmp2).
;

        .constructor    s80init, 6      ; After vt.s's (7): needs vt_active
        .destructor     s80done
        .import         __dos_type

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"
        .include        "timer.inc"

        .export         .ident(.concat(S80_API, "pan"))
        .export         .ident(.concat(S80_API, "follow"))
        .export         .ident(.concat(S80_API, "left"))
        .export         .ident(.concat(S80_API, "active"))

GAUGE_TICKS     = MS_TICKS(1000)

        .segment        "ONCE"

s80init:
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
        jsr     disp_init       ; Clears the display

        ; A buffer in BSS is cleared by crt0, and must not be written here:
        ; apple2.cfg starts BSS where ONCE starts, so clearing it would
        ; overwrite this code
        .if .not .xmatch(S80_BUFSEG, "BSS")
        jsr     clearbuf
        .endif

        ; Console output into the model.
        ; Under DOS 3.3 with DOS's video intercept in CSW, become DOS's
        ; true output routine instead: on every character through its
        ; intercepts (stdio input included), DOS copies the true handlers
        ; into CSW and KSW and reinstalls its intercepts on the way out
        ; ("Beneath Apple DOS" ch. 8, $9ED1 and $A851), which drops a
        ; routine stored in CSW directly (DESIGN.md 3.5, 3.6).
        lda     __dos_type
        bne     direct
        lda     CSWL
        cmp     DOS_VINT
        bne     direct
        lda     CSWL+1
        cmp     DOS_VINT+1
        bne     direct
        lda     #<s80_cout
        sta     DOS_CSW
        lda     #>s80_cout
        sta     DOS_CSW+1
        lda     #$80
        sta     viados
        rts
direct: lda     #<s80_cout
        sta     CSWL
        lda     #>s80_cout
        sta     CSWL+1
:       rts

        .code

s80done:
        bit     vt_active
        bmi     done

        ; Remove the gauge, if shown
        bit     gslot
        bmi     :+
        jsr     gauge_hide
:

        ; Restore the output hooks, as vt.s does
        bit     viados
        bpl     :+
        lda     savedos
        sta     DOS_CSW
        lda     savedos+1
        sta     DOS_CSW+1
        jmp     disp_done
:       lda     savecsw
        sta     CSWL
        lda     savecsw+1
        sta     CSWL+1
        lda     __dos_type
        bne     :+
        lda     DOS_CSW
        cmp     #<s80_cout
        bne     :+
        lda     DOS_CSW+1
        cmp     #>s80_cout
        bne     :+
        lda     savedos
        sta     DOS_CSW
        lda     savedos+1
        sta     DOS_CSW+1
:       jmp     disp_done
done:   rts

; ------------------------------------------------------------------------
; Output

s80_put:
        pha
        jsr     wrap
        pla
        jsr     store
        inc     s80_x           ; 80 = wrap pending
        rts

s80_putnoadv:
        pha
        jsr     wrap
        pla
        ; Fall through

; store: put screen code A at the cursor, in the buffer and, if visible,
; on the display.

store:  pha
        jsr     s80_show
        jsr     s80_bufptr
        ldy     s80_x
        pla
        pha
        eor     #$A0
        sta     (BAS2L),y
        jsr     s80_cursorcol
        tax                     ; Screen column
        pla                     ; Screen code
        bcs     :+              ; Not visible
        ldy     s80_y
        jmp     disp_cell
:       rts

; wrap: a pending wrap (column 80) becomes CR + LF.

wrap:   lda     s80_x
        cmp     #S80_COLS
        bcc     :+
        jsr     s80_cr
        jmp     s80_lf
:       rts

s80_cr: lda     #$00
        sta     s80_x
        rts

s80_lf: inc     s80_y
        lda     s80_y
        cmp     #S80_ROWS
        bcc     :+
        dec     s80_y
        jmp     scroll
:       rts

; scroll: move rows 1-23 up, clear row 23, update the display.

scroll: ldx     #$00
:       txa
        jsr     rowptrs         ; BASL = row X, BAS2L = row X + 1
        ldy     #S80_COLS-1
:       lda     (BAS2L),y
        sta     (BASL),y
        dey
        bpl     :-
        inx
        cpx     #S80_ROWS-1
        bne     :--
        lda     #S80_ROWS-1
        jsr     s80_setbuf      ; BAS2L = row 23
        lda     #$00            ; Blank
        ldy     #S80_COLS-1
:       sta     (BAS2L),y
        dey
        bpl     :-
        jmp     disp_scroll

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

s80_goto:
        cmp     #S80_ROWS
        bcs     :+
        sta     s80_y
:       cpx     #S80_COLS
        bcs     :+
        stx     s80_x
:       rts

; s80_cursorcol: the cursor's screen column (A), carry clear if visible.
; A pending wrap counts as column 79.

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

s80_clear:
        jsr     clearbuf
        lda     #$00
        sta     s80_x
        sta     s80_y
        sta     s80_left
        jmp     disp_clear

clearbuf:
        ldx     #$00
:       txa
        jsr     s80_setbuf
        lda     #$00            ; Blank
        ldy     #S80_COLS-1
:       sta     (BAS2L),y
        dey
        bpl     :-
        inx
        cpx     #S80_ROWS
        bne     :--
        rts

; s80_bufptr / s80_setbuf: BAS2L = the cursor's buffer row / buffer row A.

s80_bufptr:
        lda     s80_y
s80_setbuf:
        asl
        tay
        lda     bufrow,y
        sta     BAS2L
        lda     bufrow+1,y
        sta     BAS2L+1
        rts

; ------------------------------------------------------------------------
; COUT hook: console output, bit 7 set (stdio already applied
; uppercasemask). Preserves A, X and Y, as COUT's callers expect.

s80_cout:
        pha
        txa
        pha
        tya
        pha
        tsx
        lda     $0103,x
        cmp     #$8D            ; Return: CR + LF
        bne     :+
        jsr     s80_cr
        jsr     s80_lf
        jmp     out
:       cmp     #$8A            ; Line feed
        bne     :+
        jsr     s80_lf
        jmp     out
:       cmp     #$88            ; Backspace
        bne     :+
        jsr     back
        jmp     out
:       cmp     #$A0            ; Other controls: ignored
        bcc     out
        S80_ATTR                ; As the monitor's COUT does
        jsr     s80_put
out:    pla
        tay
        pla
        tax
        pla
        rts

; back: one column left, as the VideoTerm firmware's backspace ($C96F):
; from a pending wrap (80) to 79; from column 0 to column 79 of the row
; above (staying on row 0 at the top).

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

; gauge_show: (re)start the one-shot timer, then have the display show the
; gauge.

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

; gauge_hide: the timer's callback, also used at exit.

gauge_hide:
        lda     #$FF            ; The one-shot has freed its slot
        sta     gslot
        jmp     disp_gauge_erase

; ------------------------------------------------------------------------
; C interface

.ident(.concat(S80_API, "pan")):
        bit     vt_active
        bmi     :++
        cmp     #S80_COLS-S80_VIEW+1
        bcc     :+
        lda     #S80_COLS-S80_VIEW
:       sta     s80_left
        lda     #$00            ; Stop following
        sta     s80_follow
        jsr     disp_redraw
        jmp     gauge_show
:       rts

.ident(.concat(S80_API, "follow")):
        bit     vt_active
        bmi     :+
        lda     #$80
        sta     s80_follow
        jmp     s80_show
:       rts

.ident(.concat(S80_API, "left")):
        lda     #$00
        bit     vt_active
        bmi     :+
        lda     s80_left
:       ldx     #$00
        rts

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

s80_x:          .byte   $00
s80_y:          .byte   $00
s80_left:       .byte   $00
s80_follow:     .byte   $80     ; Bit 7: follow the cursor
gslot:          .byte   $FF     ; Gauge's timer slot; bit 7: none
viados:         .byte   $00     ; Bit 7: installed as DOS's true output routine
need:           .byte   $00
savecsw:        .word   $0000
savedos:        .word   $0000

        .segment        S80_BUFSEG

s80_buf:        .res    S80_COLS * S80_ROWS
