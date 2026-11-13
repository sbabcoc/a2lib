;
; char cgetc (void);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/cgetc.s (Kevin Ruland). With the cursor on, shows the
; VideoTerm's cursor, or a flashing caret at the window's cursor (panning
; to it if following), while waiting.
;

        .export         _cgetc
        .import         cursor

        .include        "apple2.inc"
        .include        "win.inc"
        .include        "vt.inc"
        .include        "timer.inc"

_cgetc:
        lda     cursor
        beq     wait
        bit     vt_active
        bpl     :+
        lda     #R10_BLINK
        jsr     vt_r10
        jmp     wait

        ; Window: a flashing blank, as the stock cgetc shows on a II+
:       jsr     win_show
        jsr     win_cursorcol
        bcs     wait            ; Not visible (not following)
        pha                     ; Screen column
        lda     win_y
        jsr     win_scrptr
        pla
        tay
        sty     caretcol
        lda     (BASL),y
        sta     under
        lda     #' ' | $40      ; Blank, flashing
        sta     (BASL),y
        lda     #$80
        sta     shown

        ; Wait for keyboard strobe
wait:   inc     RNDL            ; Increment random counter low
        bne     :+
        inc     RNDH            ; Increment random counter high
        jsr     a2_tickhook     ; One tick (DESIGN.md 6.3)
:       lda     KBD
        bpl     wait            ; If < 128, no key pressed
        pha

        ; Remove the cursor
        bit     vt_active
        bpl     :+
        lda     #R10_HIDDEN
        jsr     vt_r10
        jmp     :++
:       bit     shown
        bpl     :+
        lda     win_y
        jsr     win_scrptr
        ldy     caretcol
        lda     under
        sta     (BASL),y
        lda     #$00
        sta     shown

:       pla
        bit     KBDSTRB         ; Clear keyboard strobe
        and     #$7F            ; No Open-Apple on a II+
        ldx     #>$0000
        rts

        .bss

caretcol:       .res    1
under:          .res    1
shown:          .res    1
