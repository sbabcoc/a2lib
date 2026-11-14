;
; COUT routine
;
; 40-column window backend (apple2-dos33-vtwin.lib), based on cc65's
; libsrc/apple2/cout.s (Oliver Schmidt). Console output goes to the
; VideoTerm or into the window. Linking this module (all console output
; does) also links vt.s and win.s, whose constructors set up the display.
;

        .export         COUT, a2_rawcout, a2_coutvec

        .include        "win.inc"
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
        jmp     vt_write
:       jmp     win_cout
