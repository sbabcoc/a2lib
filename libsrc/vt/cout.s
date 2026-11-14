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

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "apple2.inc"
        .include        "vt.inc"

; COUT is a JMP in DATA that reflow.s's reflow_on points at its filter
; (DESIGN.md 3.7); a2_rawcout is the output routine itself.

        .data

COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1      ; The JMP's target

        .segment        "LOWCODE"

a2_rawcout:
        bit     vt_active
        bpl     :+
        jmp     vt_write        ; Same as COUT through the hook, minus banking

:       ; Switch in ROM and call COUT
        bit     $C082
        jsr     $FDED           ; Vector to user output routine

        ; Switch in LC bank 2 for R/O and return
        bit     $C080
        rts
