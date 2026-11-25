;
; 2020-07-12, Oliver Schmidt
; Scott Babcock, 2026-11-12
;
; cpeekc() for the Soft-70 library: from the VideoTerm's screen memory, or
; from the 80 x 24 model's buffer. For details, see section 3.8 of DESIGN.
;

        .export         _cpeekc

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The character at the cursor: from the model's buffer, through S80_PEEK; on
; the VideoTerm, from VRAM. A pending wrap reads column 79.
;
; Signature:    char cpeekc ()
; Overrides:    cc65's cpeekc()
; Output:       X:A           char      the character
; Changes:      Y and flags; BAS2L. On the VideoTerm: the card's VRAM page and
;               $C800 space.

_cpeekc:
        bit     vt_active
        bmi     vt

        jsr     s80_bufptr
        ldy     s80_x
        cpy     #S80_COLS
        bcc     :+
        ldy     #S80_COLS-1
:       lda     (BAS2L),y
        eor     #$A0            ; Screen code
        S80_PEEK                ; Character
        ldx     #>$0000
        rts

;-----------------------------------------------------------------------------
; cpeekc on the VideoTerm, as the VideoTerm library's: the cursor line's VRAM
; address plus the column, modulo 2048, through the $CC00-$CDFF window.
;
; Output:       X:A           char      the character, bit 7 clear
; Changes:      Y and flags; the card's VRAM page and $C800 space.

vt:     ldy     VT_CHORZ
        cpy     #VT_COLS
        bcc     :+
        ldy     #VT_COLS-1
:       bit     CLRROM          ; Select the card's $C800 space
        lda     VT_ID0
        tya
        clc
        adc     VT_BASEL
        pha
        lda     #$00
        adc     VT_BASEH
        pha
        asl
        and     #$0C
        tax
        lda     VT_CRTCREG,x    ; Select the page
        pla
        lsr                     ; Window half into C
        pla
        tax
        bcs     :+
        lda     VT_WINDOW,x
        bcc     got             ; Branch always
:       lda     VT_WINDOW+$100,x
got:    and     #$7F
        ldx     #>$0000
        rts
