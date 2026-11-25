;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; COUT for the Soft-70 library: a JMP in DATA that reflow_on() can point at
; its filter, to an output routine that writes to the VideoTerm or into the 80
; x 24 model. All console output links it, and with it the display's setup.
; For details, see section 3.8 of DESIGN.
;

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

; COUT is a JMP in DATA that reflow_on points at its filter; a2_rawcout is
; the output routine itself.

        .data

COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1      ; The JMP's target

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Write a character, as the monitor's COUT: through vt_write on the VideoTerm,
; otherwise into the model (s80_cout). Called through COUT, the JMP that
; reflow_on can point at its filter.
;
; Input:        A             char      the character, with the high bit set
; Changes:      Flags; the screen. A, X and Y are unchanged.

a2_rawcout:
        bit     vt_active
        bpl     :+
        jmp     vt_write
:       jmp     s80_cout
