;
; char cgetc (void);
;
; Soft-70 backend (apple2-dos33-vts70.lib), based on cc65's
; libsrc/apple2/cgetc.s (Kevin Ruland). With the cursor on, shows the
; VideoTerm's cursor, or Soft-70's blinking inverse cell at the cursor of
; the 80 x 24 model (s80.s; panning to it if following), while waiting.
;

        .export         _cgetc
        .import         cursor, s70_curshow, s70_curhide

        .include        "apple2.inc"
        .include        "s80.inc"
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
:       jsr     s70_curshow

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
:       jsr     s70_curhide     ; If shown

:       pla
        bit     KBDSTRB         ; Clear keyboard strobe
        and     #$7F            ; No Open-Apple on a II+
        ldx     #>$0000
        rts
