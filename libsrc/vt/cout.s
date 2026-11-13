;
; Oliver Schmidt, 03.03.2007
;
; COUT routine
;
;
; VideoTerm backend (apple2-dos33-vt.lib): modified copy of
; libsrc/apple2/cout.s from cc65; if the card is in use, writes through the
; firmware directly. Linking this module (all console output does) also
; links vt.s, whose constructor detects the card.
; (DESIGN.md 3.4).

        .export         COUT

        .include        "apple2.inc"
        .include        "vt.inc"

        .segment        "LOWCODE"

COUT:
        bit     vt_active
        bpl     :+
        jmp     vt_write        ; Same as COUT through the hook, minus banking

:       ; Switch in ROM and call COUT
        bit     $C082
        jsr     $FDED           ; Vector to user output routine

        ; Switch in LC bank 2 for R/O and return
        bit     $C080
        rts
