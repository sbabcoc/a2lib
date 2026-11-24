;
; Oliver Schmidt, 03.03.2007
; Scott Babcock, 2026-11-12
;
; COUT routine
;
; Soft-70 (a2lib-soft70.lib), with the VideoTerm; based on cc65's
; libsrc/apple2/cout.s (Oliver Schmidt). Console output goes to the
; VideoTerm or into the model (s80.s). Linking this module (all console
; output does) also links vt.s and s80.s, whose constructors set up the
; display.
;

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"

; COUT is a JMP in DATA that reflow.s's reflow_on points at its filter
; (DESIGN.md 3.7); a2_rawcout is the output routine itself.

        .data

COUT:   jmp     a2_rawcout
a2_coutvec      = COUT + 1      ; The JMP's target

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; a2_rawcout: Write a character, as the monitor's COUT: through vt_write on
; the VideoTerm, otherwise into the model (s80_cout). Called through COUT, the
; JMP that reflow_on can point at its filter.
;
; Input:        A             char      the character, with the high bit set
; Output:       none
; Changes:      Flags; the screen. A, X and Y are unchanged.

a2_rawcout:
        bit     vt_active
        bpl     :+
        jmp     vt_write
:       jmp     s80_cout
