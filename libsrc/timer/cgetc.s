;
; Kevin Ruland
; Scott Babcock, 2026-11-12
;
; char cgetc (void);
;
; If open_apple key is pressed then the high-bit of the key is set.
;
; Cooperative timer (DESIGN.md 6.3): modified copy of libsrc/apple2/cgetc.s
; from cc65. The wait loop calls a2_tickhook each time it increments RNDH.
; In a2lib-timer.lib; a2lib-timer.o pulls it in, so that cgets and cscanf,
; stock modules that call cgetc, get it too.
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
; _cgetc: Wait for a key and return it: char cgetc (void). Shows a caret while
; waiting if the cursor is on; ticks the timer while waiting.
;
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
