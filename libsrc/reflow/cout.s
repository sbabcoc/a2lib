;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-13
;
; COUT for the reflow library: as cc65's, but a JMP in DATA that reflow_on()
; can point at its filter. All stdio console output passes through it. The
; library's selector links it in place of cc65's; the display libraries have
; their own. For details, see section 3.7 of DESIGN.
;

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "apple2.inc"
        .include        "machine.inc"

        .data

COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1      ; The JMP's target

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Write a character through COUT ($FDED) with ROM banked in, as cc65's COUT
; does: the output routine itself, which COUT's JMP reaches unless reflow_on
; has pointed it at its filter.
;
; Input:        A             char      the character, with the high bit set
; Changes:      What COUT and the output hook change. Ends with LC bank 2
;               read-only.

a2_rawcout:
        ; Switch in ROM and call COUT
        bit     LC_ROM_RO
        jsr     MON_COUT        ; Vector to user output routine

        ; Switch in LC bank 2 for R/O and return
        bit     LC_BANK2_RO
        rts
