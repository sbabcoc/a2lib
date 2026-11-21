;
; 2020-07-12, Oliver Schmidt
; Scott Babcock, 2026-11-12
;
; char cpeekc (void);
;
; 80 x 24 backends (a2lib-c40win.lib, a2lib-soft70.lib), based
; on cc65's libsrc/apple2/cpeekc.s. The character at the cursor: from VRAM
; on the VideoTerm, as a2lib-vt.lib's cpeekc.s; from the model's
; buffer otherwise (S80_PEEK, display.inc). A pending wrap reads column 79.
;

        .export         _cpeekc

        .include        "apple2.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

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
