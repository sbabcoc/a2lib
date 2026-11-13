;
; Kevin Ruland
;
; char cgetc (void);
;
; If open_apple key is pressed then the high-bit of the key is set.
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/cgetc.s from cc65; if the card is in use and the cursor is
; on, shows the card's cursor while waiting, instead of drawing a caret on
; the 40-column screen (DESIGN.md 3.4).

        .export         _cgetc

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif
        .import         cursor, putchardirect

        .include        "zeropage.inc"
        .include        "apple2.inc"
        .include        "vt.inc"
        .include        "timer.inc"

_cgetc:
        bit     vt_active
        bmi     vt

        ; Cursor on ?
        lda     cursor
        beq     :+

        ; Show caret.
        .ifndef __APPLE2ENH__
        lda     #' ' | $40      ; Blank, flashing
        bit     machinetype
        bpl     put_caret
        .endif

        lda     #$7F | $80      ; Checkerboard, screen code
put_caret:
        jsr     putchardirect   ; Saves old character in tmp3

        ; Wait for keyboard strobe.
:       inc     RNDL            ; Increment random counter low
        bne     :+
        inc     RNDH            ; Increment random counter high
        jsr     a2_tickhook     ; One tick (DESIGN.md 6.3)
:       lda     KBD
        bpl     :--             ; If < 128, no key pressed

        ; Cursor on ?
        ldy     cursor
        beq     :+

        ; Restore old character.
        pha
        lda     tmp3
        jsr     putchardirect
        pla

        ; At this time, the high bit of the key pressed is set.
:
strobe: bit     KBDSTRB         ; Clear keyboard strobe

        .ifndef __APPLE2ENH__
        bit     machinetype     ; Apple //e or more recent?
        bpl     clear
        .endif
        bit     BUTN0           ; Check if OpenApple is down
        bmi     done

clear:  and     #$7F            ; If not down, then clear high bit
done:   ldx     #>$0000
        rts

vt:     lda     cursor          ; Cursor on? Show the card's
        beq     :+
        lda     #R10_BLINK
        jsr     vt_r10
:       inc     RNDL            ; Increment random counter low
        bne     :+
        inc     RNDH            ; Increment random counter high
        jsr     a2_tickhook     ; One tick (DESIGN.md 6.3)
:       lda     KBD
        bpl     :--             ; If < 128, no key pressed
        pha
        lda     #R10_HIDDEN
        jsr     vt_r10
        pla
        jmp     strobe
