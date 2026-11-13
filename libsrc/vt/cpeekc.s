;
; 2020-07-12, Oliver Schmidt
;
; char cpeekc (void);
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/cpeekc.s from cc65; if the card is in use, reads the character
; at its cursor from VRAM, locating it as the firmware's $CA59 does.
; (DESIGN.md 3.4).

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .export         _cpeekc

        .include        "apple2.inc"
        .include        "vt.inc"

_cpeekc:
        bit     vt_active
        bmi     vt
        ldy     CH

        sec                     ; Assume main memory

        .ifndef __APPLE2ENH__
        bit     machinetype
        bpl     peek
        .endif

        bit     RD80VID         ; In 80 column mode?
        bpl     peek            ; No, just go ahead
        lda     OURCH
        lsr                     ; Div by 2
        tay
        bcs     peek            ; Odd cols are in main memory
        php
        sei                     ; No valid MSLOT et al. in aux memory
        bit     HISCR           ; Assume SET80COL

peek:   lda     (BASL),Y        ; Get character
        bcs     :+              ; In main memory
        bit     LOWSCR
        plp

:       eor     #$80            ; Invert high bit
        ldx     #>$0000
        rts

; VRAM address = line base (VT_BASEH/VT_BASEL, kept by the firmware for the
; cursor's row) + column, modulo 2048. Bits 1-2 of the high byte select one
; of four 512-byte pages, bit 0 the half of the $CC00-$CDFF window.

vt:     ldy     VT_CHORZ
        cpy     #VT_COLS
        bcc     :+
        ldy     #VT_COLS-1      ; Wrap pending: the last column
:       bit     CLRROM          ; Select the card's $C800 space, where the
        lda     VT_ID0          ; window is: any access to its slot ROM
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
:       and     #$7F            ; Bit 7 is the character set
        ldx     #>$0000
        rts
