;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; cgetc() for the timer library, as cc65's, with a wait loop that ticks the
; cooperative timer each time it increments RNDH. The library's selector links
; it, so that cgets() and cscanf() get it too.
;
; If open_apple key is pressed then the high-bit of the key is set.
;
; For details, see section 6.3 of DESIGN.
;

        .export         _cgetc

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif
        .import         cursor, putchardirect

        .include        "zeropage.inc"
        .include        "apple2.inc"
        .include        "timer.inc"

;-----------------------------------------------------------------------------
; Wait for a key. Shows a caret while waiting if the cursor is on, and ticks
; the timer.
;
; Signature:    char cgetc ()
; Overrides:    cc65's cgetc()
; Input:        cursor        byte      nonzero: show the caret
; Output:       AX            char      the key, with the high bit set if Open
;                                       Apple is down on a IIe or later
; Changes:      Y; tmp3 (putchardirect); RNDL and RNDH; KBDSTRB, cleared; what
;               a2_tick changes.

_cgetc:
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
        jsr     a2_tickhook     ; One tick
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
:       bit     KBDSTRB         ; Clear keyboard strobe

        .ifndef __APPLE2ENH__
        bit     machinetype     ; Apple //e or more recent?
        bpl     clear
        .endif
        bit     BUTN0           ; Check if OpenApple is down
        bmi     done

clear:  and     #$7F            ; If not down, then clear high bit
done:   ldx     #>$0000
        rts
