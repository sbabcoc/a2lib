;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; COUT for the VideoTerm library: a JMP in DATA that reflow_on() can point at
; its filter, to an output routine that writes through the card's firmware
; while it is in use. All console output links it, and with it the card's
; detection. For details, see section 3.4 of DESIGN.
;

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "apple2.inc"
        .include        "machine.inc"
        .include        "vt.inc"

; COUT is a JMP in DATA that reflow_on points at its filter; a2_rawcout is
; the output routine itself.

        .data

COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1      ; The JMP's target

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Write a character, as the monitor's COUT: through vt_write on the card,
; otherwise through COUT ($FDED) with ROM banked in. Called through COUT, the
; JMP that reflow_on can point at its filter.
;
; Input:        A             char      the character, with the high bit set
; Changes:      On the card: flags only. Otherwise: what COUT and the output
;               hook change. Ends with LC bank 2 read-only.

a2_rawcout:
        bit     vt_active
        bpl     :+
        jmp     vt_write        ; Same as COUT through the hook, minus banking

:       ; Switch in ROM and call COUT
        bit     LC_ROM_RO
        jsr     MON_COUT        ; Vector to user output routine

        ; Switch in LC bank 2 for R/O and return
        bit     LC_BANK2_RO
        rts
