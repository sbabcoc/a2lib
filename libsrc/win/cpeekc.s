;
; char cpeekc (void);
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/cpeekc.s. The character at the cursor: from VRAM on the
; VideoTerm, as apple2-dos33-vt.lib's cpeekc.s; from the 80 x 24 buffer
; otherwise. A pending wrap reads column 79.
;

        .export         _cpeekc

        .include        "apple2.inc"
        .include        "win.inc"
        .include        "vt.inc"

_cpeekc:
        bit     vt_active
        bmi     vt

        jsr     win_bufptr
        ldy     win_x
        cpy     #WIN_COLS
        bcc     :+
        ldy     #WIN_COLS-1
:       lda     (BAS2L),y
        eor     #$A0            ; Screen code
        eor     #$80            ; Character, as the stock cpeekc
        ldx     #>$0000
        rts

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
        bcc     :++             ; Branch always
:       lda     VT_WINDOW+$100,x
:       and     #$7F
        ldx     #>$0000
        rts
