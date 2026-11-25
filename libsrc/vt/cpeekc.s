;
; 2020-07-12, Oliver Schmidt
; Scott Babcock, 2026-11-12
;
; cpeekc() for the VideoTerm library: on the card, from its screen memory,
; found as the firmware finds the cursor. For details, see section 3.4 of
; DESIGN.
;

        .ifndef __APPLE2ENH__
        .import         machinetype
        .endif

        .export         _cpeekc

        .include        "apple2.inc"
        .include        "vt.inc"

;-----------------------------------------------------------------------------
; The character at the cursor. On the card, read from VRAM where the
; firmware's $CA59 finds it, using the last column while a wrap is pending.
;
; Signature:    char cpeekc ()
; Overrides:    cc65's cpeekc()
; Output:       AX            char      the character
; Changes:      Y and flags. On the card: the card's VRAM page and $C800
;               space.

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

;-----------------------------------------------------------------------------
; cpeekc on the card. The VRAM address is the cursor line's base
; (VT_BASEH/VT_BASEL, kept by the firmware) plus the column, modulo 2048: bits
; 1-2 of its high byte select one of four 512-byte pages, and bit 0 the half
; of the $CC00-$CDFF window.
;
; Input:        VT_CHORZ      byte      the cursor's column (80: wrap pending)
;               VT_BASEL      word      the cursor line's VRAM address (high
;                                       byte in VT_BASEH)
; Output:       AX            char      the character, bit 7 clear (bit 7 is
;                                       the character set)
; Changes:      Y and flags; the card's VRAM page and $C800 space.

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
        bcc     got             ; Branch always
:       lda     VT_WINDOW+$100,x
got:    and     #$7F            ; Bit 7 is the character set
        ldx     #>$0000
        rts
