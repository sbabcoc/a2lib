;
; Oliver Schmidt, 03.03.2007
;
; COUT routine
;
; Reflow support (DESIGN.md 3.7): modified copy of libsrc/apple2/cout.s
; from cc65. COUT, through which all stdio console output passes (write.s,
; and read.s for its echo), is a JMP in DATA that reflow.s's reflow_on
; points at its filter; a2_rawcout is the stock routine. Programs that
; never call reflow_on pay 3 bytes and 3 cycles per character.
;

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "apple2.inc"

        .data

COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1      ; The JMP's target

        .segment        "LOWCODE"

a2_rawcout:
        ; Switch in ROM and call COUT
        bit     $C082
        jsr     $FDED           ; Vector to user output routine

        ; Switch in LC bank 2 for R/O and return
        bit     $C080
        rts
