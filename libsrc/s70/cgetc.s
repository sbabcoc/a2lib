;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; cgetc() for the Soft-70 library. With the cursor on, it shows the
; VideoTerm's cursor, or Soft-70's blinking inverse cell at the model's
; cursor, panning to it if following. For details, see section 3.8 of DESIGN.
;

        .export         _cgetc
        .import         cursor, s70_curshow, s70_curhide

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "vt.inc"
        .include        "timer.inc"

;-----------------------------------------------------------------------------
; Wait for a key. If the cursor is on, shows the VideoTerm's cursor, or
; Soft-70's blinking cursor at the model's, panning to it if following. Ticks
; the timer.
;
; Signature:    char cgetc ()
; Overrides:    cc65's cgetc()
; Input:        cursor        byte      nonzero: show the cursor
; Output:       X:A           char      the key, high bit clear (no Open Apple
;                                       on a II+)
; Changes:      Y and flags; RNDL and RNDH; KBDSTRB, cleared; what a2_tick,
;               s70_curshow and s70_curhide change.

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
        jsr     a2_tickhook     ; One tick
:       lda     KBD
        bpl     wait            ; If < 128, no key pressed
        pha

        ; Remove the cursor
        bit     vt_active
        bpl     :+
        lda     #R10_HIDDEN
        jsr     vt_r10
        jmp     hidden
:       jsr     s70_curhide     ; If shown

hidden: pla
        bit     KBDSTRB         ; Clear keyboard strobe
        and     #$7F            ; No Open-Apple on a II+
        ldx     #>$0000
        rts
